# cbor.ex — LTX v1.1 minimal deterministic CBOR, RFC 8949 (Epic 72).
# Mirrors typescript/ltx/src/cbor.ts (Story 70.1 — zero-dependency subset
# for COSE_Sign1, RFC 9052).
#
# Supported: unsigned/negative integers, byte strings, text strings, arrays,
# maps, booleans, null, and tags. Encoding follows the RFC 8949 §4.2.1 core
# deterministic profile: definite lengths only, shortest-form integer heads,
# map keys sorted bytewise by their encoded form. Floats, indefinite lengths
# and trailing bytes are rejected.

defmodule InterplanetLtx.Cbor do
  @moduledoc """
  Value mapping Elixir ⇄ CBOR: integer ⇄ major 0/1, `{:bstr, binary}` ⇄
  major 2, binary (UTF-8 string) ⇄ major 3, list ⇄ major 4, map ⇄ major 5,
  `{:tag, n, value}` ⇄ major 6, true/false/nil ⇄ major 7. Decoded map keys
  that are byte strings are converted to base64url strings.
  """

  # ── Encoding ────────────────────────────────────────────────────────────────

  @doc "Encode a value to deterministic CBOR bytes."
  def encode(nil), do: <<0xF6>>
  def encode(true), do: <<0xF5>>
  def encode(false), do: <<0xF4>>

  def encode(v) when is_integer(v) do
    if v >= 0, do: encode_head(0, v), else: encode_head(1, -v - 1)
  end

  def encode({:bstr, b}) when is_binary(b), do: encode_head(2, byte_size(b)) <> b

  def encode(s) when is_binary(s), do: encode_head(3, byte_size(s)) <> s

  def encode({:tag, n, v}) when is_integer(n), do: encode_head(6, n) <> encode(v)

  def encode(list) when is_list(list) do
    encode_head(4, length(list)) <> Enum.map_join(list, "", &encode/1)
  end

  def encode(map) when is_map(map) do
    # Deterministic: sort by encoded key bytes (RFC 8949 §4.2.1).
    encoded =
      map
      |> Enum.map(fn {k, v} -> {encode(k), encode(v)} end)
      |> Enum.sort_by(fn {kb, _} -> kb end)

    encode_head(5, map_size(map)) <> Enum.map_join(encoded, "", fn {kb, vb} -> kb <> vb end)
  end

  def encode(other), do: raise(ArgumentError, "cbor: unsupported type #{inspect(other)}")

  defp encode_head(major, arg) when arg >= 0 do
    cond do
      arg < 24 -> <<major::3, arg::5>>
      arg < 0x100 -> <<major::3, 24::5, arg::8>>
      arg < 0x10000 -> <<major::3, 25::5, arg::16>>
      arg < 0x100000000 -> <<major::3, 26::5, arg::32>>
      true -> <<major::3, 27::5, arg::64>>
    end
  end

  # ── Decoding ────────────────────────────────────────────────────────────────

  @doc """
  Decode deterministic CBOR bytes to a value. Raises on floats, indefinite
  lengths, unsupported simple values, truncation, or trailing bytes.
  """
  def decode(bytes) when is_binary(bytes) do
    {value, rest} = decode_item(bytes)
    if rest != <<>>, do: raise(ArgumentError, "cbor: trailing bytes")
    value
  end

  defp decode_item(<<0xF6, r::binary>>), do: {nil, r}
  defp decode_item(<<0xF5, r::binary>>), do: {true, r}
  defp decode_item(<<0xF4, r::binary>>), do: {false, r}

  defp decode_item(<<major::3, info::5, r::binary>>) do
    {arg, r} = read_arg(info, r)

    case major do
      0 ->
        {arg, r}

      1 ->
        {-arg - 1, r}

      2 ->
        case r do
          <<b::binary-size(arg), r2::binary>> -> {{:bstr, b}, r2}
          _ -> raise ArgumentError, "cbor: truncated bstr"
        end

      3 ->
        case r do
          <<b::binary-size(arg), r2::binary>> -> {b, r2}
          _ -> raise ArgumentError, "cbor: truncated tstr"
        end

      4 ->
        Enum.map_reduce(1..arg//1, r, fn _, acc -> decode_item(acc) end)

      5 ->
        {pairs, r2} =
          Enum.map_reduce(1..arg//1, r, fn _, acc ->
            {k, acc1} = decode_item(acc)
            {v, acc2} = decode_item(acc1)
            k = with {:bstr, kb} <- k, do: Base.url_encode64(kb, padding: false)
            {{k, v}, acc2}
          end)

        {Map.new(pairs), r2}

      6 ->
        {v, r2} = decode_item(r)
        {{:tag, arg, v}, r2}

      _ ->
        raise ArgumentError, "cbor: unsupported major type #{major} / simple value"
    end
  end

  defp decode_item(<<>>), do: raise(ArgumentError, "cbor: truncated")

  defp read_arg(info, r) when info < 24, do: {info, r}
  defp read_arg(24, <<v::8, r::binary>>), do: {v, r}
  defp read_arg(25, <<v::16, r::binary>>), do: {v, r}
  defp read_arg(26, <<v::32, r::binary>>), do: {v, r}
  defp read_arg(27, <<v::64, r::binary>>), do: {v, r}

  defp read_arg(info, _) when info >= 28,
    do: raise(ArgumentError, "cbor: indefinite lengths not supported")

  defp read_arg(_, _), do: raise(ArgumentError, "cbor: truncated")
end
