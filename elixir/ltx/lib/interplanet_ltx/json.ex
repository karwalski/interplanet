# json.ex -- dependency-free JSON for the LTX port.
#
# Elixir maps do not keep insertion order, but the FROZEN v2 planId hash is
# computed over JSON.stringify of the plan in insertion order
# (LTX-SPECIFICATION.md §4.3). This module therefore offers an ordered decode
# (objects as `{:object, [{key, value}]}`), a JSON.stringify-compatible
# encoder for ordered values, and the imul31 hash over UTF-16 code units.
# It needs no Hex package and no OTP 27 `:json`, so it runs on Elixir 1.14+.

defmodule InterplanetLtx.Json do
  @moduledoc """
  Minimal JSON support: `decode!/1` (plain maps), `decode_ordered!/1`
  (insertion-ordered objects as `{:object, pairs}`), `to_plain/1`,
  `stringify/1` (byte-for-byte `JSON.stringify` for ordered or plain values)
  and `imul31_hex/1` (the frozen v2 planId hash).
  """

  import Bitwise

  # ── Decoding ────────────────────────────────────────────────────────────────

  @doc "Decode JSON text; objects become string-keyed maps."
  def decode!(text) when is_binary(text), do: text |> decode_ordered!() |> to_plain()

  @doc "Decode JSON text; objects become `{:object, [{key, value}]}` in source order."
  def decode_ordered!(text) when is_binary(text) do
    {value, rest} = value(skip_ws(text))

    case skip_ws(rest) do
      "" -> value
      other -> raise ArgumentError, "json: trailing data #{inspect(String.slice(other, 0, 20))}"
    end
  end

  @doc "Convert ordered values (from `decode_ordered!/1`) to plain maps and lists."
  def to_plain({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, to_plain(v)} end)
  def to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)
  def to_plain(v), do: v

  @doc "Look up a key in an ordered object (or a plain map)."
  def get({:object, pairs}, key) do
    case List.keyfind(pairs, key, 0) do
      {_, v} -> v
      nil -> nil
    end
  end

  def get(map, key) when is_map(map), do: Map.get(map, key)
  def get(_, _), do: nil

  @doc """
  Set a key in an ordered object with JS object-spread semantics: an existing
  key keeps its position, a new key is appended.
  """
  def put({:object, pairs}, key, value) do
    if List.keymember?(pairs, key, 0),
      do: {:object, List.keyreplace(pairs, key, 0, {key, value})},
      else: {:object, pairs ++ [{key, value}]}
  end

  defp skip_ws(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_ws(rest)
  defp skip_ws(s), do: s

  defp value("{" <> rest), do: object(skip_ws(rest), [])
  defp value("[" <> rest), do: array(skip_ws(rest), [])
  defp value("\"" <> rest), do: string(rest, [])
  defp value("true" <> rest), do: {true, rest}
  defp value("false" <> rest), do: {false, rest}
  defp value("null" <> rest), do: {nil, rest}
  defp value(s), do: number(s)

  defp object("}" <> rest, []), do: {{:object, []}, rest}

  defp object("\"" <> rest, acc) do
    {key, rest} = string(rest, [])
    ":" <> rest = skip_ws(rest)
    {val, rest} = value(skip_ws(rest))
    acc = [{key, val} | acc]

    case skip_ws(rest) do
      "," <> rest -> object(skip_ws(rest), acc)
      "}" <> rest -> {{:object, Enum.reverse(acc)}, rest}
      _ -> raise ArgumentError, "json: expected , or } in object"
    end
  end

  defp object(_, _), do: raise(ArgumentError, "json: expected object key")

  defp array("]" <> rest, []), do: {[], rest}

  defp array(s, acc) do
    {val, rest} = value(s)

    case skip_ws(rest) do
      "," <> rest -> array(skip_ws(rest), [val | acc])
      "]" <> rest -> {Enum.reverse([val | acc]), rest}
      _ -> raise ArgumentError, "json: expected , or ] in array"
    end
  end

  defp string("\"" <> rest, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  # A surrogate pair escape is joined into one code point. A lone surrogate
  # escape (valid JSON; JSON.stringify writes one for a lone surrogate, e.g.
  # a planId whose cut split a pair) cannot be held by a UTF-8 string and
  # decodes to U+FFFD, as when JS encodes that string to UTF-8.
  defp string("\\u" <> <<hex::binary-size(4), rest::binary>>, acc) do
    cp = String.to_integer(hex, 16)

    cond do
      cp in 0xD800..0xDBFF ->
        with "\\u" <> <<lo_hex::binary-size(4), rest2::binary>> <- rest,
             lo when lo in 0xDC00..0xDFFF <- String.to_integer(lo_hex, 16) do
          full = 0x10000 + ((cp - 0xD800) <<< 10) + (lo - 0xDC00)
          string(rest2, [<<full::utf8>> | acc])
        else
          _ -> string(rest, ["\uFFFD" | acc])
        end

      cp in 0xDC00..0xDFFF ->
        string(rest, ["\uFFFD" | acc])

      true ->
        string(rest, [<<cp::utf8>> | acc])
    end
  end

  defp string("\\" <> <<c, rest::binary>>, acc) do
    ch =
      case c do
        ?n -> "\n"
        ?t -> "\t"
        ?r -> "\r"
        ?b -> "\b"
        ?f -> "\f"
        ?/ -> "/"
        ?\\ -> "\\"
        ?" -> "\""
        _ -> raise ArgumentError, "json: bad escape"
      end

    string(rest, [ch | acc])
  end

  defp string(<<c::utf8, rest::binary>>, acc), do: string(rest, [<<c::utf8>> | acc])
  defp string(_, _), do: raise(ArgumentError, "json: unterminated string")

  defp number(s) do
    {tok, rest} = take_number(s, [])

    if tok == "" do
      raise ArgumentError, "json: unexpected input #{inspect(String.slice(s, 0, 20))}"
    end

    if String.contains?(tok, [".", "e", "E"]) do
      case Float.parse(tok) do
        {f, ""} -> {f, rest}
        _ -> raise ArgumentError, "json: bad number #{tok}"
      end
    else
      {String.to_integer(tok), rest}
    end
  end

  defp take_number(<<c, rest::binary>>, acc) when c in ~c"0123456789+-.eE",
    do: take_number(rest, [c | acc])

  defp take_number(rest, acc), do: {acc |> Enum.reverse() |> List.to_string(), rest}

  # ── Encoding (JSON.stringify semantics) ─────────────────────────────────────

  @doc """
  Serialise like JavaScript `JSON.stringify`: no whitespace, ordered objects
  in their stored order, plain maps in map order, integral floats without a
  fraction. Strings escape `"`, `\\` and control characters exactly as V8 does.
  """
  def stringify({:object, pairs}) do
    "{" <> Enum.map_join(pairs, ",", fn {k, v} -> quote_str(to_string(k)) <> ":" <> stringify(v) end) <> "}"
  end

  def stringify(list) when is_list(list), do: "[" <> Enum.map_join(list, ",", &stringify/1) <> "]"
  def stringify(map) when is_map(map) and not is_struct(map), do: stringify({:object, Map.to_list(map)})
  def stringify(true), do: "true"
  def stringify(false), do: "false"
  def stringify(nil), do: "null"
  def stringify(v) when is_integer(v), do: Integer.to_string(v)

  def stringify(v) when is_float(v) do
    if v == Float.round(v) and abs(v) < 1.0e21,
      do: v |> trunc() |> Integer.to_string(),
      else: :erlang.float_to_binary(v, [:short])
  end

  def stringify(v) when is_binary(v), do: quote_str(v)
  def stringify(v) when is_atom(v), do: quote_str(Atom.to_string(v))

  defp quote_str(s) do
    escaped =
      for <<c::utf8 <- s>>, into: "" do
        case c do
          ?" -> "\\\""
          ?\\ -> "\\\\"
          ?\b -> "\\b"
          ?\f -> "\\f"
          ?\n -> "\\n"
          ?\r -> "\\r"
          ?\t -> "\\t"
          c when c < 0x20 -> "\\u" <> (c |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))
          c -> <<c::utf8>>
        end
      end

    "\"" <> escaped <> "\""
  end

  # ── Frozen v2 hash ──────────────────────────────────────────────────────────

  @doc """
  `h = (Math.imul(31, h) + charCodeAt(i)) >>> 0` over the UTF-16 code units
  of `s`, as 8 lowercase hex digits (LTX-SPECIFICATION.md §4.3).
  """
  def imul31_hex(s) when is_binary(s) do
    utf16 = :unicode.characters_to_binary(s, :utf8, {:utf16, :big})

    h =
      for <<unit::16 <- utf16>>, reduce: 0 do
        acc -> band(acc * 31 + unit, 0xFFFFFFFF)
      end

    h |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(8, "0")
  end
end
