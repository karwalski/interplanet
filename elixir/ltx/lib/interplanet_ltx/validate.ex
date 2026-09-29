# validate.ex — plan validation (LTX-SPECIFICATION.md §3.5, §4, §7).
# Mirrors validatePlan / _reservedFieldErrors / _assertNoReservedFields in
# javascript/ltx/ltx-sdk.js and typescript/ltx/src/validate.ts.

defmodule InterplanetLtx.ReservedFieldError do
  @moduledoc """
  Raised by `upgrade_plan_to_v3`, `create_amendment` and `create_session` when
  a plan uses reserved stream or branching fields. `code` is the first error
  code ("reserved_streams" or "reserved_branching"); `errors` lists them all.
  """
  defexception [:message, :code, errors: []]
end

defmodule InterplanetLtx.Validate do
  @moduledoc """
  `validate_plan/1` checks a v2 or v3 plan (string-keyed map, `LtxPlan`
  struct, or ordered `{:object, pairs}` from `InterplanetLtx.Json`) against
  the wire format (spec/ltx-schema.json) and the reserved-field rules. It is
  pure and never raises; it returns `%{valid: boolean, errors: [error]}` with
  each error `%{code: string, path: string, message: string}`.

  Error codes: not_an_object, invalid_version, missing_field, invalid_field,
  invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
  duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
  invalid_delays, reserved_streams, reserved_branching.
  """

  alias InterplanetLtx.Models.LtxPlan

  @seg_types ["PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE"]
  @plan_segment_types @seg_types ++ ["SPEAK", "REST", "PAD", "OPEN", "RELAY"]
  @plan_modes ["LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC"]
  @v3_only_fields ["delays", "planVersion", "prevPlanHash", "questions", "actions", "streams"]
  @reserved_branch_plan_fields ["branches", "branching"]
  @reserved_branch_segment_fields ["branch"]
  @reserved_stream_segment_fields ["stream"]
  @node_roles ["HOST", "PARTICIPANT", "OBSERVER"]

  def plan_segment_types, do: @plan_segment_types
  def plan_modes, do: @plan_modes
  def v3_only_fields, do: @v3_only_fields

  # ── Normalisation ───────────────────────────────────────────────────────────

  defp normalise(%LtxPlan{} = plan), do: InterplanetLtx.Segments.plan_map(plan)
  defp normalise({:object, _} = obj), do: InterplanetLtx.Json.to_plain(obj)
  defp normalise(v), do: v

  # ── Reserved fields (§3.5 streams, §7 branching) ────────────────────────────

  @doc "Reserved-field violations only (§3.5 streams, §7 branching)."
  def reserved_field_errors(plan) do
    plan = normalise(plan)

    if is_map(plan) do
      streams_err =
        if Map.has_key?(plan, "streams") and plan["streams"] != [] do
          [err("reserved_streams", "streams",
               "streams[] is reserved (§3.5) and MUST be absent or empty")]
        else
          []
        end

      branch_errs =
        for f <- @reserved_branch_plan_fields, Map.has_key?(plan, f) do
          err("reserved_branching", f,
              "#{f} is reserved for branching (§7, not yet implemented) and MUST be absent")
        end

      segs = if is_list(plan["segments"]), do: plan["segments"], else: []

      seg_errs =
        segs
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {s, i} when is_map(s) ->
            (for f <- @reserved_stream_segment_fields, Map.has_key?(s, f) do
               err("reserved_streams", "segments[#{i}].#{f}",
                   "segment #{f} is reserved (§3.5) and MUST be absent")
             end) ++
              (for f <- @reserved_branch_segment_fields, Map.has_key?(s, f) do
                 err("reserved_branching", "segments[#{i}].#{f}",
                     "segment #{f} is reserved for branching (§7) and MUST be absent")
               end)

          _ ->
            []
        end)

      streams_err ++ branch_errs ++ seg_errs
    else
      []
    end
  end

  @doc """
  Raise `InterplanetLtx.ReservedFieldError` if a plan uses reserved
  stream/branch fields; `fn_name` prefixes the message.
  """
  def assert_no_reserved_fields!(plan, fn_name) do
    case reserved_field_errors(plan) do
      [] ->
        :ok

      [first | _] = errors ->
        raise InterplanetLtx.ReservedFieldError,
          message: "#{fn_name}: #{first.message}",
          code: first.code,
          errors: errors
    end
  end

  # ── validate_plan ───────────────────────────────────────────────────────────

  @doc "Validate a v2 or v3 plan. Pure; never raises."
  def validate_plan(plan) do
    plan = normalise(plan)

    if not is_map(plan) or is_struct(plan) do
      %{valid: false, errors: [err("not_an_object", "", "plan must be an object")]}
    else
      {errors, ids} = {[], MapSet.new()}
      has = &Map.has_key?(plan, &1)
      v = plan["v"]

      errors = errors ++ if v == 2 or v == 3, do: [], else: [err("invalid_version", "v", "v must be 2 or 3")]

      errors =
        errors ++
          for f <- ["title", "start", "quantum", "mode", "nodes", "segments"], not has.(f) do
            err("missing_field", f, "#{f} is required")
          end

      errors =
        errors ++
          if has.("title") and not is_binary(plan["title"]),
            do: [err("invalid_field", "title", "title must be a string")],
            else: []

      errors =
        errors ++
          if has.("start") and not valid_timestamp?(plan["start"]),
            do: [err("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")],
            else: []

      errors =
        errors ++
          if has.("quantum") and not (js_integer?(plan["quantum"]) and plan["quantum"] >= 1 and plan["quantum"] <= 60),
            do: [err("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)")],
            else: []

      errors =
        errors ++
          if has.("mode") and plan["mode"] not in @plan_modes,
            do: [err("invalid_mode", "mode", "mode must be one of #{Enum.join(@plan_modes, ", ")}")],
            else: []

      {node_errors, ids} = if has.("nodes"), do: check_nodes(plan["nodes"]), else: {[], ids}
      errors = errors ++ node_errors

      errors = errors ++ if has.("segments"), do: check_segments(plan["segments"], ids), else: []

      errors =
        errors ++
          cond do
            v == 2 ->
              for f <- @v3_only_fields, has.(f) do
                err("v3_field_in_v2", f, "#{f} is a v3 field and MUST NOT appear in a v2 plan (§4.3)")
              end

            v == 3 ->
              check_v3(plan, ids)

            true ->
              []
          end

      errors = errors ++ reserved_field_errors(plan)
      %{valid: errors == [], errors: errors}
    end
  end

  defp check_nodes(nodes) when is_list(nodes) and nodes != [] do
    {errs, ids, hosts} =
      nodes
      |> Enum.with_index()
      |> Enum.reduce({[], MapSet.new(), 0}, fn {n, i}, {errs, ids, hosts} ->
        if valid_node?(n) do
          errs =
            if MapSet.member?(ids, n["id"]),
              do: errs ++ [err("duplicate_node_id", "nodes[#{i}].id", "duplicate node id #{n["id"]}")],
              else: errs

          {errs, MapSet.put(ids, n["id"]), if(n["role"] == "HOST", do: hosts + 1, else: hosts)}
        else
          {errs ++
             [err("invalid_nodes", "nodes[#{i}]",
                  "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0")],
           ids, hosts}
        end
      end)

    h = hd(nodes)

    host_ok =
      hosts == 1 and is_map(h) and h["role"] == "HOST" and is_number(h["delay"]) and h["delay"] == 0

    errs =
      if host_ok,
        do: errs,
        else: errs ++ [err("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)")]

    {errs, ids}
  end

  defp check_nodes(_), do: {[err("invalid_nodes", "nodes", "nodes must be a non-empty array")], MapSet.new()}

  defp valid_node?(n) do
    is_map(n) and is_binary(n["id"]) and n["id"] != "" and not String.contains?(n["id"], "|") and
      is_binary(n["name"]) and n["role"] in @node_roles and is_number(n["delay"]) and n["delay"] >= 0
  end

  defp check_segments(segs, ids) when is_list(segs) do
    segs
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, i} ->
      cond do
        not (is_map(s) and s["type"] in @plan_segment_types and js_integer?(s["q"]) and s["q"] >= 1) ->
          [err("invalid_segment", "segments[#{i}]", "segment needs a known type and integer q >= 1")]

        Map.has_key?(s, "speaker") and not MapSet.member?(ids, s["speaker"]) ->
          [err("unknown_speaker", "segments[#{i}].speaker", "speaker #{s["speaker"]} is not a node id")]

        true ->
          []
      end
    end)
  end

  defp check_segments(_, _), do: [err("invalid_segment", "segments", "segments must be an array")]

  defp check_v3(plan, ids) do
    delay_errs =
      if Map.has_key?(plan, "delays") do
        d = plan["delays"]

        if is_map(d) do
          for {k, val} <- d, not valid_delay_entry?(k, val, ids) do
            err("invalid_delays", "delays.#{k}",
                "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)")
          end
        else
          [err("invalid_delays", "delays", "delays must be an object")]
        end
      else
        []
      end

    pv_errs =
      if Map.has_key?(plan, "planVersion") and not (js_integer?(plan["planVersion"]) and plan["planVersion"] >= 1),
        do: [err("invalid_field", "planVersion", "planVersion must be an integer >= 1")],
        else: []

    ph = plan["prevPlanHash"]

    ph_errs =
      if Map.has_key?(plan, "prevPlanHash") and not (is_binary(ph) and Regex.match?(~r/\A[0-9a-f]{64}\z/, ph)),
        do: [err("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")],
        else: []

    arr_errs =
      for f <- ["questions", "actions"], Map.has_key?(plan, f), not is_list(plan[f]) do
        err("invalid_field", f, "#{f} must be an array")
      end

    delay_errs ++ pv_errs ++ ph_errs ++ arr_errs
  end

  defp valid_delay_entry?(k, val, ids) do
    case String.split(k, "|") do
      [a, b] ->
        a < b and (MapSet.size(ids) == 0 or (MapSet.member?(ids, a) and MapSet.member?(ids, b))) and
          is_number(val) and val >= 0

      _ ->
        false
    end
  end

  # Number.isInteger: integers, and floats with no fractional part.
  defp js_integer?(v) when is_integer(v), do: true
  defp js_integer?(v) when is_float(v), do: v == Float.round(v)
  defp js_integer?(_), do: false

  # Date.parse(...) is finite: accept ISO 8601 date-times (with or without an
  # offset) and plain dates.
  defp valid_timestamp?(s) when is_binary(s) do
    match?({:ok, _, _}, DateTime.from_iso8601(s)) or match?({:ok, _}, NaiveDateTime.from_iso8601(s)) or
      match?({:ok, _}, Date.from_iso8601(s))
  end

  defp valid_timestamp?(_), do: false

  defp err(code, path, message), do: %{code: code, path: path, message: message}
end
