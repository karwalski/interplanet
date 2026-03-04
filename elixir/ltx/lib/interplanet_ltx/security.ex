# security.ex — Epic 29 security cascade for InterplanetLtx (Elixir)
# Stories 29.1, 29.4, 29.5
# Uses Erlang :crypto for Ed25519 (OTP 22+)

defmodule InterplanetLtx.Security do
  @moduledoc """
  NIK generation, plan signing/verification, and sequence tracking.
  Uses Erlang :crypto for Ed25519 (OTP 22+).
  """

  # ── Canonical JSON ─────────────────────────────────────────────────────────

  @doc "Produce a deterministic, sorted-key JSON string."
  def canonical_json(value) when is_map(value) do
    sorted = value |> Enum.sort_by(fn {k, _} -> k end)
    inner =
      sorted
      |> Enum.map(fn {k, v} ->
        json_str(to_string(k)) <> ":" <> canonical_json(v)
      end)
      |> Enum.join(",")
    "{" <> inner <> "}"
  end

  def canonical_json(value) when is_list(value) do
    "[" <> (value |> Enum.map(&canonical_json/1) |> Enum.join(",")) <> "]"
  end

  def canonical_json(true),  do: "true"
  def canonical_json(false), do: "false"
  def canonical_json(nil),   do: "null"
  def canonical_json(v) when is_integer(v), do: Integer.to_string(v)
  def canonical_json(v) when is_float(v),
    do: :erlang.float_to_binary(v, [:compact, {:decimals, 15}])
  def canonical_json(v) when is_binary(v), do: json_str(v)
  def canonical_json(v) when is_atom(v),   do: json_str(Atom.to_string(v))

  defp json_str(s) do
    inner =
      s
      |> String.to_charlist()
      |> Enum.map_join(fn
        ?"  -> "\\\""
        ?\\ -> "\\\\"
        ?\n -> "\\n"
        ?\r -> "\\r"
        ?\t -> "\\t"
        c when c < 0x20 ->
          :io_lib.format("\\u~4.16.0b", [c]) |> IO.chardata_to_string()
        c -> <<c::utf8>>
      end)
    "\"" <> inner <> "\""
  end

  # ── generate_nik ───────────────────────────────────────────────────────────

  @doc """
  Generate a new Node Identity Key (NIK).
  Options: valid_days (default 365), node_label (default "").
  Returns %{nik: map, private_key_b64: string}.
  """
  def generate_nik(opts \\ []) do
    valid_days = Keyword.get(opts, :valid_days, 365)
    node_label = Keyword.get(opts, :node_label, "")

    # :crypto.generate_key(:eddsa, :ed25519) returns {pub_32_bytes, priv_32_bytes}
    {pub_raw, priv_raw} = :crypto.generate_key(:eddsa, :ed25519)

    hash    = :crypto.hash(:sha256, pub_raw)
    node_id = hash |> binary_part(0, 16) |> b64u()

    now_ms   = :os.system_time(:millisecond)
    until_ms = now_ms + valid_days * 86_400_000

    nik = %{
      "nodeId"     => node_id,
      "publicKey"  => b64u(pub_raw),
      "algorithm"  => "Ed25519",
      "validFrom"  => ms_to_iso(now_ms),
      "validUntil" => ms_to_iso(until_ms),
      "keyVersion" => 1
    }
    nik = if node_label != "", do: Map.put(nik, "label", node_label), else: nik

    # Store public key alongside private key so we can derive kid later without re-deriving
    %{nik: nik, private_key_b64: b64u(priv_raw), _pub_raw: pub_raw}
  end

  # ── is_nik_expired ─────────────────────────────────────────────────────────

  @doc "Returns true if the NIK validUntil is in the past."
  def is_nik_expired(%{"validUntil" => valid_until}) do
    :os.system_time(:millisecond) > parse_iso_ms(valid_until)
  end
  def is_nik_expired(_), do: true

  # ── sign_plan ──────────────────────────────────────────────────────────────

  @doc """
  Sign an LTX plan.
  private_key_b64 is base64url of the raw 32-byte Ed25519 private key.
  pub_key_b64 (optional) is the matching public key — needed to derive kid.
  Returns %{plan: plan, coseSign1: map}.
  """
  def sign_plan(plan, private_key_b64, pub_key_b64 \\ nil) do
    protected_b64 = b64u(canonical_json(%{"alg" => -19}))
    payload_b64   = b64u(canonical_json(normalise(plan)))

    msg      = canonical_json(["Signature1", protected_b64, "", payload_b64])
               |> :erlang.iolist_to_binary()
    priv_raw = unb64u(private_key_b64)
    sig      = :crypto.sign(:eddsa, :none, msg, [priv_raw, :ed25519])

    kid =
      if pub_key_b64 do
        unb64u(pub_key_b64)
        |> (&:crypto.hash(:sha256, &1)).()
        |> binary_part(0, 16)
        |> b64u()
      else
        # Cannot derive kid without pub key — use a placeholder
        # This case should be avoided; callers should pass the pub key
        b64u(:crypto.hash(:sha256, priv_raw) |> binary_part(0, 16))
      end

    %{
      plan: plan,
      coseSign1: %{
        "protected"   => protected_b64,
        "unprotected" => %{"kid" => kid},
        "payload"     => payload_b64,
        "signature"   => b64u(sig)
      }
    }
  end

  # ── verify_plan ────────────────────────────────────────────────────────────

  @doc "Verify a COSE_Sign1-signed plan envelope."
  def verify_plan(%{coseSign1: cs, plan: plan}, key_cache), do: do_verify(cs, plan, key_cache)
  def verify_plan(%{"coseSign1" => cs, "plan" => plan}, key_cache), do: do_verify(cs, plan, key_cache)

  defp do_verify(cs, plan, key_cache) do
    kid        = (cs["unprotected"] || %{})["kid"]
    signer_nik = find_nik(key_cache, kid)

    cond do
      is_nil(signer_nik) ->
        %{valid: false, reason: "key_not_in_cache"}
      is_nik_expired(signer_nik) ->
        %{valid: false, reason: "key_expired"}
      true ->
        protected = cs["protected"]
        payload   = cs["payload"]
        sig_b64   = cs["signature"]

        msg       = canonical_json(["Signature1", protected, "", payload])
                    |> :erlang.iolist_to_binary()
        sig_bytes = unb64u(sig_b64)
        pub_raw   = unb64u(signer_nik["publicKey"])
        valid     = :crypto.verify(:eddsa, :none, msg, sig_bytes, [pub_raw, :ed25519])

        cond do
          not valid ->
            %{valid: false, reason: "signature_invalid"}
          unb64u(payload) != canonical_json(normalise(plan)) ->
            %{valid: false, reason: "payload_mismatch"}
          true ->
            %{valid: true}
        end
    end
  end

  defp find_nik(cache, kid) when is_map(cache) do
    Map.get(cache, kid) ||
      Enum.find_value(cache, fn {_k, v} ->
        if (v["nodeId"] || v[:nodeId]) == kid, do: v, else: nil
      end)
  end
  defp find_nik(_, _), do: nil

  # ── SequenceTracker ────────────────────────────────────────────────────────

  @doc "Create a new in-memory sequence tracker."
  def new_sequence_tracker(plan_id) do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    %{plan_id: plan_id, pid: pid, prefix: "ltx_seq_#{plan_id}_"}
  end

  @doc "Get next outbound sequence number for node_id."
  def next_seq(%{pid: pid, prefix: prefix}, node_id) do
    key = prefix <> node_id
    Agent.get_and_update(pid, fn store ->
      n = Map.get(store, key, 0) + 1
      {n, Map.put(store, key, n)}
    end)
  end

  @doc "Add :seq field to a bundle map."
  def add_seq(bundle, tracker, node_id) do
    Map.put(bundle, :seq, next_seq(tracker, node_id))
  end

  @doc "Check incoming seq from sender."
  def check_seq(bundle, tracker, sender_node_id) do
    seq = Map.get(bundle, :seq) || Map.get(bundle, "seq")
    if is_nil(seq) or not is_integer(seq) do
      %{accepted: false, reason: "missing_seq", gap: false, gap_size: 0}
    else
      record_seq(tracker, sender_node_id, seq)
    end
  end

  defp record_seq(%{pid: pid, prefix: prefix}, node_id, seq) do
    key = prefix <> node_id <> "_rx"
    Agent.get_and_update(pid, fn store ->
      last = Map.get(store, key, 0)
      {result, new_store} =
        cond do
          seq <= last ->
            {%{accepted: false, reason: "replay", gap: false, gap_size: 0}, store}
          seq == last + 1 ->
            {%{accepted: true, reason: nil, gap: false, gap_size: 0}, Map.put(store, key, seq)}
          true ->
            gs = seq - last - 1
            {%{accepted: true, reason: nil, gap: true, gap_size: gs}, Map.put(store, key, seq)}
        end
      {result, new_store}
    end)
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp b64u(bytes) when is_binary(bytes), do: Base.url_encode64(bytes, padding: false)
  defp b64u(str)  when is_list(str),      do: str |> IO.chardata_to_string() |> b64u()
  defp unb64u(s), do: Base.url_decode64!(s, padding: false)

  defp normalise(v) when is_struct(v) do
    v |> Map.from_struct()
    |> Enum.reduce(%{}, fn {k, val}, acc ->
      Map.put(acc, Atom.to_string(k), normalise(val))
    end)
  end
  defp normalise(v) when is_list(v),  do: Enum.map(v, &normalise/1)
  defp normalise(v) when is_atom(v) and v not in [true, false, nil], do: Atom.to_string(v)
  defp normalise(v), do: v

  defp ms_to_iso(ms) do
    secs   = div(ms, 1000)
    ms_rem = rem(ms, 1000)
    {{y, mo, d}, {h, mi, s}} =
      :calendar.gregorian_seconds_to_datetime(secs + 62_167_219_200)
    :io_lib.format(
      "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
      [y, mo, d, h, mi, s, ms_rem]
    ) |> IO.chardata_to_string()
  end

  defp parse_iso_ms(nil), do: 0
  defp parse_iso_ms(""),  do: 0
  defp parse_iso_ms(str) when is_binary(str) do
    case Regex.run(
      ~r/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?Z?$/,
      str
    ) do
      [_, y, mo, d, h, mi, s | rest] ->
        ms_s = case rest do
          [ms] -> ms |> String.slice(0, 3) |> String.pad_trailing(3, "0")
          _    -> "000"
        end
        dt = {
          {String.to_integer(y), String.to_integer(mo), String.to_integer(d)},
          {String.to_integer(h), String.to_integer(mi), String.to_integer(s)}
        }
        gsecs = :calendar.datetime_to_gregorian_seconds(dt) - 62_167_219_200
        gsecs * 1000 + String.to_integer(ms_s)
      _ -> 0
    end
  end
end
