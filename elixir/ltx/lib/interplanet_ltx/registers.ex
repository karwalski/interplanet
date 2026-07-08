# registers.ex — LTX v1.1 question/action registers (Epic 72).
# Mirrors typescript/ltx/src/registers.ts (Story 69.1 —
# LTX-SPECIFICATION.md §9/§10, LTX-SECURITY.md §9.5/§9.6).
#
# Registers are not mutable state: they are deterministic reductions over
# the signed, append-only audit log. Entries are ordered by
# (timestamp, nodeId, seq) and object-level conflicts resolve by highest
# object version, then lexicographically lowest editor nodeId (§8.2).

defmodule InterplanetLtx.Registers do
  @moduledoc """
  Signed register entries (string-keyed maps with envelope
  `entryId/sessionId/nodeId/seq/type/content/timestamp/sig`), deterministic
  ordering, question/action reducers, and the Merkle entries root.
  """

  alias InterplanetLtx.Security

  @entry_prefix %{
    "question" => "QST",
    "question_response" => "QST",
    "action" => "ACT",
    "action_update" => "ACT",
    "amendment" => "AMD",
    "state_transition" => "STA",
    "merge_snapshot" => "MRG",
    "decision" => "DEC"
  }

  @action_statuses ["PROPOSED", "ACCEPTED", "REJECTED", "DONE"]

  # ── Entry creation and verification ─────────────────────────────────────────

  @doc """
  Create a signed register entry (LTX-SECURITY.md §9.5). The Ed25519
  signature covers the canonical JSON of the entry without `sig`.
  Required opts: `session_id`, `node_id`, `seq`, `timestamp`,
  `private_key_b64`; optional `entry_id`.
  """
  def create_register_entry(type, content, opts) do
    entry_id =
      Keyword.get(opts, :entry_id) ||
        "#{@entry_prefix[type]}-#{Keyword.fetch!(opts, :node_id)}-#{Keyword.fetch!(opts, :seq)}"

    unsigned = %{
      "entryId" => entry_id,
      "sessionId" => Keyword.fetch!(opts, :session_id),
      "nodeId" => Keyword.fetch!(opts, :node_id),
      "seq" => Keyword.fetch!(opts, :seq),
      "type" => type,
      "content" => content,
      "timestamp" => Keyword.fetch!(opts, :timestamp)
    }

    priv_raw = unb64u(Keyword.fetch!(opts, :private_key_b64))
    sig = :crypto.sign(:eddsa, :none, Security.canonical_json(unsigned), [priv_raw, :ed25519])
    Map.put(unsigned, "sig", b64u(sig))
  end

  @doc """
  Verify a register entry signature against a key cache mapping the entry's
  nodeId to its NIK. Returns `%{valid: bool, reason: string?}`.
  """
  def verify_register_entry(entry, key_cache) do
    sig = is_map(entry) && entry["sig"]

    cond do
      !sig ->
        %{valid: false, reason: "missing_sig"}

      true ->
        case key_cache[entry["nodeId"]] do
          nil ->
            %{valid: false, reason: "key_not_in_cache"}

          nik ->
            unsigned = Map.delete(entry, "sig")
            pub_raw = unb64u(nik["publicKey"])

            ok =
              :crypto.verify(
                :eddsa, :none,
                Security.canonical_json(unsigned),
                unb64u(sig),
                [pub_raw, :ed25519]
              )

            if ok, do: %{valid: true}, else: %{valid: false, reason: "signature_invalid"}
        end
    end
  end

  # ── Deterministic ordering (LTX-SPECIFICATION.md §8.2) ──────────────────────

  @doc "Total order key: (timestamp, nodeId, seq)."
  def entry_order_key(e), do: {e["timestamp"], e["nodeId"], e["seq"]}

  @doc "De-duplicate by (nodeId, seq) — first occurrence wins — and sort into the §8.2 total order."
  def order_entries(entries) do
    entries
    |> Enum.reduce({[], MapSet.new()}, fn e, {acc, seen} ->
      key = {e["nodeId"], e["seq"]}

      if MapSet.member?(seen, key) do
        {acc, seen}
      else
        {[e | acc], MapSet.put(seen, key)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.sort_by(&entry_order_key/1)
  end

  # ── Reducers ────────────────────────────────────────────────────────────────

  # §8.2 conflict rule: higher version wins; tie → lowest editor nodeId.
  defp wins?(incoming, current) do
    if incoming.version != current.version,
      do: incoming.version > current.version,
      else: incoming.editor < current.editor
  end

  @doc """
  Reduce question register state from log entries (LTX-SPECIFICATION.md §9.4).
  Pure: identical entry sets (in any input order) produce identical state.
  Returns `%{by_id: %{qid => state}, superseded: [entryId]}` with string-keyed
  question-state maps.
  """
  def reduce_questions(entries) do
    {by_id, _winners, superseded} =
      Enum.reduce(order_entries(entries), {%{}, %{}, []}, fn e, {by_id, winners, sup} ->
        content = e["content"] || %{}

        case e["type"] do
          "question" ->
            qid = e["entryId"]

            if Map.has_key?(by_id, qid) do
              {by_id, winners, sup ++ [e["entryId"]]}
            else
              state =
                %{
                  "qid" => qid,
                  "text" => to_string(content["text"] || ""),
                  "submitter" => e["nodeId"],
                  "status" => "OPEN",
                  "version" => 1
                }
                |> put_if(content, "urgency")
                |> put_if(content, "intendedWindow")

              winner = %{version: 1, editor: e["nodeId"], entry_id: e["entryId"]}
              {Map.put(by_id, qid, state), Map.put(winners, qid, winner), sup}
            end

          "question_response" ->
            qid = to_string(content["qid"] || "")

            case by_id[qid] do
              nil ->
                {by_id, winners, sup ++ [e["entryId"]]}

              q ->
                version = content["version"] || q["version"] + 1
                incoming = %{version: version, editor: e["nodeId"], entry_id: e["entryId"]}
                current = winners[qid]

                if current && not wins?(incoming, current) do
                  {by_id, winners, sup ++ [e["entryId"]]}
                else
                  sup =
                    if current && current.entry_id != q["qid"],
                      do: sup ++ [current.entry_id],
                      else: sup

                  status =
                    if content["status"] == "WITHDRAWN", do: "WITHDRAWN", else: "ANSWERED"

                  state =
                    q
                    |> Map.merge(%{
                      "status" => status,
                      "responder" => e["nodeId"],
                      "version" => version
                    })
                    |> put_if(content, "response")

                  {Map.put(by_id, qid, state), Map.put(winners, qid, incoming), sup}
                end
            end

          _ ->
            {by_id, winners, sup}
        end
      end)

    %{by_id: by_id, superseded: superseded}
  end

  @doc """
  Reduce action register state from log entries (LTX-SPECIFICATION.md §10.2).
  Returns `%{by_id: %{aid => state}, superseded: [entryId]}`.
  """
  def reduce_actions(entries) do
    {by_id, _winners, superseded} =
      Enum.reduce(order_entries(entries), {%{}, %{}, []}, fn e, {by_id, winners, sup} ->
        content = e["content"] || %{}

        case e["type"] do
          "action" ->
            aid = e["entryId"]

            if Map.has_key?(by_id, aid) do
              {by_id, winners, sup ++ [e["entryId"]]}
            else
              state =
                %{
                  "aid" => aid,
                  "description" => to_string(content["description"] || ""),
                  "status" => "PROPOSED",
                  "version" => 1
                }
                |> put_if(content, "owner")
                |> put_if(content, "dueTimeUTC")
                |> put_if(content, "originWindow")

              winner = %{version: 1, editor: e["nodeId"], entry_id: e["entryId"]}
              {Map.put(by_id, aid, state), Map.put(winners, aid, winner), sup}
            end

          "action_update" ->
            aid = to_string(content["aid"] || "")

            case by_id[aid] do
              nil ->
                {by_id, winners, sup ++ [e["entryId"]]}

              a ->
                version = content["version"] || a["version"] + 1
                incoming = %{version: version, editor: e["nodeId"], entry_id: e["entryId"]}
                current = winners[aid]

                if current && not wins?(incoming, current) do
                  {by_id, winners, sup ++ [e["entryId"]]}
                else
                  sup =
                    if current && current.entry_id != a["aid"],
                      do: sup ++ [current.entry_id],
                      else: sup

                  status =
                    if content["status"] in @action_statuses,
                      do: content["status"],
                      else: a["status"]

                  state =
                    a
                    |> Map.merge(%{"status" => status, "version" => version})
                    |> put_if(content, "description")
                    |> put_if(content, "owner")
                    |> put_if(content, "dueTimeUTC")

                  {Map.put(by_id, aid, state), Map.put(winners, aid, incoming), sup}
                end
            end

          _ ->
            {by_id, winners, sup}
        end
      end)

    %{by_id: by_id, superseded: superseded}
  end

  defp put_if(state, content, key) do
    if Map.has_key?(content, key),
      do: Map.put(state, key, to_string(content[key])),
      else: state
  end

  # ── Merkle entries root (RFC 9162-style; mirrors merkle.ts) ─────────────────

  @doc """
  Merkle audit-log root (hex) over the ordered entries.
  Leaf hash: SHA-256(0x00 || canonicalJSON(entry)); node hash:
  SHA-256(0x01 || left || right); empty root: 64 hex zeros.
  """
  def entries_root(entries) do
    entries
    |> order_entries()
    |> Enum.map(fn e -> :crypto.hash(:sha256, <<0>> <> Security.canonical_json(e)) end)
    |> root_of()
    |> Base.encode16(case: :lower)
  end

  defp root_of([]), do: <<0::size(256)>>
  defp root_of([leaf]), do: leaf

  defp root_of(leaves) do
    n = length(leaves)
    mid = Bitwise.bsl(1, bit_width(n - 1) - 1)
    {left, right} = Enum.split(leaves, mid)
    :crypto.hash(:sha256, <<1>> <> root_of(left) <> root_of(right))
  end

  # Number of bits needed to represent n (n >= 1).
  defp bit_width(n), do: bit_width(n, 0)
  defp bit_width(0, acc), do: acc
  defp bit_width(n, acc), do: bit_width(Bitwise.bsr(n, 1), acc + 1)

  # ── base64url helpers ───────────────────────────────────────────────────────

  defp b64u(bytes), do: Base.url_encode64(bytes, padding: false)
  defp unb64u(s), do: Base.url_decode64!(s, padding: false)
end
