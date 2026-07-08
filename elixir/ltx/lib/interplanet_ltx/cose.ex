# cose.ex — LTX v1.1 COSE_Sign1 (RFC 9052) plan verification (Epic 72).
# Mirrors typescript/ltx/src/cose.ts (Story 70.2 — real CBOR COSE_Sign1
# alongside the frozen TRANSITIONAL JSON envelope, LTX-SECURITY.md §7.2/§7.5).
#
# Algorithm: Ed25519, COSE algorithm ID -19 (RFC 9864; the polymorphic EdDSA
# id -8 is deprecated and rejected). Payload: canonical JSON bytes of the
# plan. Structure: COSE_Sign1 = tag 18 of
#   [ protected: bstr .cbor { 1: -19 },
#     unprotected: { 4: kid-bytes },
#     payload: bstr,
#     signature: bstr ]
# Sig_structure = ["Signature1", protected, external_aad = h'', payload].

defmodule InterplanetLtx.Cose do
  @moduledoc """
  CBOR COSE_Sign1 signing/verification for LTX plans. Envelopes are maps
  `%{"plan" => plan, "coseSign1CborB64" => b64u}`. Verification is the
  conformance requirement; signing is provided for completeness.
  """

  alias InterplanetLtx.Cbor
  alias InterplanetLtx.Security

  @cose_sign1_tag 18
  @cose_alg_ed25519 -19

  def cose_sign1_tag, do: @cose_sign1_tag
  def cose_alg_ed25519, do: @cose_alg_ed25519

  defp sig_structure(protected_bytes, payload) do
    Cbor.encode(["Signature1", {:bstr, protected_bytes}, {:bstr, <<>>}, {:bstr, payload}])
  end

  @doc """
  Sign a plan as a real CBOR COSE_Sign1 (tag 18). The kid (header label 4)
  is the first 16 bytes of SHA-256(raw public key), matching
  `Security.generate_nik/1`.
  """
  def sign_plan_cose(plan, private_key_b64) do
    priv_raw = unb64u(private_key_b64)
    {pub_raw, _} = :crypto.generate_key(:eddsa, :ed25519, priv_raw)

    protected_bytes = Cbor.encode(%{1 => @cose_alg_ed25519})
    payload = Security.canonical_json(plan)
    signature = :crypto.sign(:eddsa, :none, sig_structure(protected_bytes, payload), [priv_raw, :ed25519])
    kid = :crypto.hash(:sha256, pub_raw) |> binary_part(0, 16)

    cose_sign1 =
      {:tag, @cose_sign1_tag,
       [{:bstr, protected_bytes}, %{4 => {:bstr, kid}}, {:bstr, payload}, {:bstr, signature}]}

    %{"plan" => plan, "coseSign1CborB64" => b64u(Cbor.encode(cose_sign1))}
  end

  @doc """
  Verify a CBOR COSE_Sign1 plan envelope against the key cache
  (kid → NIK map; NIKs are string-keyed maps as in `Security`).
  Rejects non-Ed25519 algorithms (including the deprecated -8) and payloads
  that do not match the accompanying plan. Returns `%{valid: bool, reason: string?}`.
  """
  def verify_plan_cose(envelope, key_cache) do
    b64 = is_map(envelope) && (envelope["coseSign1CborB64"] || envelope[:coseSign1CborB64])

    if !is_binary(b64) do
      %{valid: false, reason: "missing_cose_sign1"}
    else
      case safe_decode(b64) do
        :error ->
          %{valid: false, reason: "cbor_decode_failed"}

        {:ok, {:tag, @cose_sign1_tag, [{:bstr, protected_bytes}, unprotected, {:bstr, payload}, {:bstr, signature}]}} ->
          verify_parts(envelope, key_cache, protected_bytes, unprotected, payload, signature)

        {:ok, {:tag, @cose_sign1_tag, _}} ->
          %{valid: false, reason: "malformed_cose_sign1"}

        {:ok, _} ->
          %{valid: false, reason: "not_cose_sign1"}
      end
    end
  end

  defp verify_parts(envelope, key_cache, protected_bytes, unprotected, payload, signature) do
    plan = envelope["plan"] || envelope[:plan]

    protected_map =
      case safe_cbor(protected_bytes) do
        {:ok, m} when is_map(m) -> m
        _ -> nil
      end

    kid =
      case is_map(unprotected) && Map.get(unprotected, 4) do
        {:bstr, kid_bytes} -> b64u(kid_bytes)
        kid when is_binary(kid) -> kid
        _ -> ""
      end

    cond do
      is_nil(protected_map) ->
        %{valid: false, reason: "protected_decode_failed"}

      protected_map[1] != @cose_alg_ed25519 ->
        %{valid: false, reason: "unsupported_alg"}

      kid == "" ->
        %{valid: false, reason: "missing_kid"}

      true ->
        signer_nik = find_nik(key_cache, kid)

        cond do
          is_nil(signer_nik) ->
            %{valid: false, reason: "key_not_in_cache"}

          Security.is_nik_expired(signer_nik) ->
            %{valid: false, reason: "key_expired"}

          not :crypto.verify(
            :eddsa, :none,
            sig_structure(protected_bytes, payload),
            signature,
            [unb64u(signer_nik["publicKey"]), :ed25519]
          ) ->
            %{valid: false, reason: "signature_invalid"}

          plan != nil and payload != Security.canonical_json(plan) ->
            %{valid: false, reason: "payload_mismatch"}

          true ->
            %{valid: true}
        end
    end
  end

  @doc """
  Verify either envelope form: the CBOR COSE_Sign1 (`coseSign1CborB64`) or
  the frozen TRANSITIONAL JSON envelope (`coseSign1`) — LTX-SECURITY.md §7.5.
  """
  def verify_plan_any(envelope, key_cache) do
    cond do
      is_map(envelope) and (envelope["coseSign1CborB64"] || envelope[:coseSign1CborB64]) != nil ->
        verify_plan_cose(envelope, key_cache)

      is_map(envelope) and (envelope["coseSign1"] || envelope[:coseSign1]) != nil ->
        Security.verify_plan(envelope, key_cache)

      true ->
        %{valid: false, reason: "unknown_envelope"}
    end
  end

  defp find_nik(cache, kid) when is_map(cache) do
    Map.get(cache, kid) ||
      Enum.find_value(cache, fn {_k, n} ->
        node_id = n["nodeId"] || n[:nodeId]
        if is_binary(node_id) and String.starts_with?(node_id, kid), do: n
      end)
  end

  defp find_nik(_, _), do: nil

  defp safe_decode(b64) do
    with {:ok, bytes} <- Base.url_decode64(b64, padding: false),
         {:ok, value} <- safe_cbor(bytes) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp safe_cbor(bytes) do
    try do
      {:ok, Cbor.decode(bytes)}
    rescue
      _ -> :error
    end
  end

  defp b64u(bytes), do: Base.url_encode64(bytes, padding: false)
  defp unb64u(s), do: Base.url_decode64!(s, padding: false)
end
