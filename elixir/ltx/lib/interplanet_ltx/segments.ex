# segments.ex — LTX v1.1 core subset (Epic 72): v3 planId, pairDelay,
# computeSegmentsFor. Mirrors typescript/ltx/src/segments.ts.

defmodule InterplanetLtx.Segments do
  @moduledoc """
  v1.1 segment/plan-id functions over raw plan maps (v2 or v3).

  v2 plans keep the FROZEN legacy 32-bit polynomial planId hash over the
  insertion-order JSON (LTX-SPECIFICATION.md §4.3, via `InterplanetLtx`);
  v3 plans hash SHA-256 over RFC 8785 canonical JSON (§4.5) with a `-v3-`
  infix so the two id spaces stay disjoint.
  """

  alias InterplanetLtx.Security
  alias InterplanetLtx.Models.LtxPlan

  # ── Plan normalisation ──────────────────────────────────────────────────────

  @doc """
  Normalise a plan (LtxPlan struct, or v1/v2/v3 string-keyed map) to a
  string-keyed plan map. v2+/nodes maps are returned unchanged so v3 fields
  (`delays`, `planVersion`, `prevPlanHash`) survive.
  """
  def plan_map(%LtxPlan{} = plan) do
    %{
      "v" => plan.v,
      "title" => plan.title,
      "start" => plan.start,
      "quantum" => plan.quantum,
      "mode" => plan.mode,
      "nodes" =>
        Enum.map(plan.nodes, fn n ->
          %{"id" => n.id, "name" => n.name, "role" => n.role,
            "delay" => n.delay, "location" => n.location}
        end),
      "segments" =>
        Enum.map(plan.segments, fn s ->
          %{"type" => s.type, "q" => s.q}
          |> then(fn m -> if s.speaker, do: Map.put(m, "speaker", s.speaker), else: m end)
          |> then(fn m -> if s.label, do: Map.put(m, "label", s.label), else: m end)
        end)
    }
  end

  def plan_map(cfg) when is_map(cfg) do
    v = cfg["v"] || cfg[:v] || 1
    nodes = cfg["nodes"] || cfg[:nodes]

    if is_integer(v) and v >= 2 and is_list(nodes) and nodes != [] do
      cfg
    else
      plan_map(InterplanetLtx.upgrade_config(cfg))
    end
  end

  # ── Plan ID (v2 frozen / v3 canonical) ──────────────────────────────────────

  @doc """
  Compute the deterministic plan ID string.
  v3 plan maps use SHA-256 over canonical JSON; anything else delegates to
  the frozen v2 path in `InterplanetLtx.make_plan_id/1`.
  """
  def make_plan_id(%LtxPlan{} = plan), do: InterplanetLtx.make_plan_id(plan)

  def make_plan_id(cfg) when is_map(cfg) do
    v = cfg["v"] || cfg[:v] || 1

    if is_integer(v) and v >= 3 do
      c = plan_map(cfg)
      date = c["start"] |> to_string() |> String.slice(0, 10) |> String.replace("-", "")
      nodes = c["nodes"] || []

      host_str =
        case nodes do
          [first | _] -> short_name(first["name"] || "HOST", 8)
          [] -> "HOST"
        end

      node_str =
        case nodes do
          [_ | rest] when rest != [] ->
            rest
            |> Enum.map_join("-", fn n -> short_name(n["name"] || "", 4) end)
            |> String.slice(0, 16)

          _ -> "RX"
        end

      digest =
        :crypto.hash(:sha256, Security.canonical_json(c))
        |> Base.encode16(case: :lower)

      "LTX-#{date}-#{host_str}-#{node_str}-v3-#{String.slice(digest, 0, 8)}"
    else
      InterplanetLtx.make_plan_id(cfg)
    end
  end

  defp short_name(name, len) do
    name
    |> String.replace(~r/\s+/, "")
    |> String.upcase()
    |> String.slice(0, len)
  end

  # ── pair_delay (LTX-SPECIFICATION.md §3.7) ──────────────────────────────────

  @doc """
  One-way delay in seconds between two nodes. The v3 pair matrix
  (`plan["delays"]`, sorted-id `"A|B"` keys) is authoritative where present;
  otherwise the conservative fallback: HOST pairs use the node's declared
  delay, non-HOST pairs the sum of both HOST-relative delays.
  """
  def pair_delay(plan, node_id_a, node_id_b) do
    c = plan_map(plan)

    if node_id_a == node_id_b do
      0
    else
      delays = c["delays"]
      key = [node_id_a, node_id_b] |> Enum.sort() |> Enum.join("|")

      if is_map(delays) and is_number(delays[key]) do
        delays[key]
      else
        nodes = c["nodes"] || []
        a = Enum.find(nodes, fn n -> n["id"] == node_id_a end)
        b = Enum.find(nodes, fn n -> n["id"] == node_id_b end)

        if is_nil(a) or is_nil(b) do
          raise ArgumentError,
                "pair_delay: unknown node #{if is_nil(a), do: node_id_a, else: node_id_b}"
        end

        host_id = List.first(nodes)["id"]

        cond do
          node_id_a == host_id -> b["delay"] || 0
          node_id_b == host_id -> a["delay"] || 0
          true -> (a["delay"] || 0) + (b["delay"] || 0)
        end
      end
    end
  end

  # ── compute_segments_for (LTX-SPECIFICATION.md §14.3) ───────────────────────

  @doc """
  Compute the timed segment list from viewer V's perspective: a segment
  attributed to speaker S starts for V at seg_start + pair_delay(S, V).
  Unattributed segments keep their times.

  Returns a list of maps: `%{type:, q:, start_ms:, end_ms:, dur_min:,
  speaker:, label:, perspective:, arrival_offset_s:}` where `perspective`
  is "transmit", "receive" or "neutral" (speaker/label omitted when unset).
  """
  def compute_segments_for(plan, viewer_node_id) do
    c = plan_map(plan)
    nodes = c["nodes"] || []

    unless Enum.any?(nodes, fn n -> n["id"] == viewer_node_id end) do
      raise ArgumentError, "compute_segments_for: unknown viewer #{viewer_node_id}"
    end

    q_ms = (c["quantum"] || 0) * 60 * 1000
    t0 = iso_ms(c["start"])

    {segs, _} =
      Enum.map_reduce(c["segments"] || [], t0, fn s, t ->
        dur_ms = s["q"] * q_ms
        speaker = s["speaker"]

        base = %{
          type: s["type"],
          q: s["q"],
          start_ms: t,
          end_ms: t + dur_ms,
          dur_min: s["q"] * (c["quantum"] || 0)
        }

        base =
          base
          |> then(fn m -> if speaker, do: Map.put(m, :speaker, speaker), else: m end)
          |> then(fn m -> if s["label"], do: Map.put(m, :label, s["label"]), else: m end)

        seg =
          cond do
            is_nil(speaker) or s["type"] not in ["TX", "SPEAK"] ->
              Map.merge(base, %{perspective: "neutral", arrival_offset_s: 0})

            speaker == viewer_node_id ->
              Map.merge(base, %{perspective: "transmit", arrival_offset_s: 0})

            true ->
              shift_s = pair_delay(c, speaker, viewer_node_id)

              Map.merge(base, %{
                start_ms: t + shift_s * 1000,
                end_ms: t + dur_ms + shift_s * 1000,
                perspective: "receive",
                arrival_offset_s: shift_s
              })
          end

        {seg, t + dur_ms}
      end)

    segs
  end

  defp iso_ms(nil), do: 0

  defp iso_ms(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> DateTime.to_unix(dt, :millisecond)
      _ -> 0
    end
  end
end
