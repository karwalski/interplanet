# frozen_string_literal: true

# js_json.rb — JSON serialisation byte-compatible with JavaScript.
#
# The frozen v2 planId (LTX-SPECIFICATION.md §4.3) hashes the UTF-16 code
# units of JSON.stringify(plan), and canonical JSON (§4.5) serialises scalars
# with JSON.stringify. Ruby's to_json prints integral floats as "840.0" and
# uses a different exponent format, so these helpers follow ECMAScript
# (Number::toString and JSON.stringify) instead.

require 'json'

module InterplanetLtx
  module JsJson
    module_function

    # One or more characters of ECMAScript \s (WhiteSpace and LineTerminator,
    # ES2024 §12.2 and §12.3). Ruby's \s matches ASCII whitespace only.
    WHITESPACE = /[\t\n\v\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+/.freeze

    # Format a number exactly as JavaScript's JSON.stringify does.
    def number(x)
      return x.to_s if x.is_a?(Integer)
      return 'null' unless x.finite?
      return '0' if x.zero?

      sign = x.negative? ? '-' : ''
      mant, exp = x.abs.to_s.split('e')
      int_part, frac = mant.split('.')
      digits = int_part + (frac || '')
      n = int_part.length + exp.to_i # decimal point position
      while digits.length > 1 && digits.start_with?('0')
        digits = digits[1..]
        n -= 1
      end
      digits = digits.sub(/0+\z/, '')
      digits = '0' if digits.empty?
      k = digits.length
      return sign + digits + ('0' * (n - k)) if k <= n && n <= 21
      return sign + digits[0, n] + '.' + digits[n..] if n.positive? && n <= 21
      return sign + '0.' + ('0' * -n) + digits if n > -6 && n <= 0

      e = n - 1
      es = (e >= 0 ? '+' : '-') + e.abs.to_s
      return sign + digits + 'e' + es if k == 1

      sign + digits[0] + '.' + digits[1..] + 'e' + es
    end

    # Quote a string exactly as JavaScript's JSON.stringify does.
    #
    # Ruby's generator already escapes exactly as JSON.stringify does
    # (\b \t \n \f \r, other C0 controls as lowercase \u00xx, no escaping
    # of "/", DEL or U+2028/U+2029). A UTF-8 String cannot hold a lone UTF-16
    # surrogate, but a WTF-8 String can (bytes ED A0..BF xx); JSON.stringify
    # writes a lone surrogate as a lowercase \udxxx escape, and so does this.
    def string(s)
      s = s.to_s
      return JSON.generate(s) if s.valid_encoding?

      _wtf8_string(s)
    end

    # JSON.stringify of a String that is not valid UTF-8: decode it as WTF-8
    # (lone surrogates escaped, a CESU-8 surrogate pair joined into one code
    # point); any other invalid byte raises.
    def _wtf8_string(s)
      bytes = s.b
      out = +'"'
      text = +''
      i = 0
      while i < bytes.bytesize
        b = bytes.getbyte(i)
        len = b < 0x80 ? 1 : b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : 2
        chunk = bytes.byteslice(i, len).force_encoding('UTF-8')
        if chunk.valid_encoding?
          text << chunk
        elsif len == 3 && b == 0xED && (0xA0..0xBF).cover?(bytes.getbyte(i + 1).to_i) &&
              (0x80..0xBF).cover?(bytes.getbyte(i + 2).to_i)
          unit = 0xD000 | ((bytes.getbyte(i + 1) & 0x3F) << 6) | (bytes.getbyte(i + 2) & 0x3F)
          nxt = bytes.byteslice(i + 3, 3).bytes
          if unit < 0xDC00 && nxt.size == 3 && nxt[0] == 0xED && (0xB0..0xBF).cover?(nxt[1]) &&
             (0x80..0xBF).cover?(nxt[2])
            low = 0xD000 | ((nxt[1] & 0x3F) << 6) | (nxt[2] & 0x3F)
            text << (0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)).chr(Encoding::UTF_8)
            len = 6
          else
            out << JSON.generate(text)[1...-1] << format('\u%04x', unit)
            text = +''
          end
        else
          raise JSON::GeneratorError, 'source sequence is illegal/malformed utf-8'
        end
        i += len
      end
      out << JSON.generate(text)[1...-1] << '"'
    end

    # JSON.stringify(obj) with no whitespace, preserving Hash insertion order.
    def stringify(obj)
      case obj
      when nil then 'null'
      when true then 'true'
      when false then 'false'
      when Numeric then number(obj)
      when String, Symbol then string(obj.to_s)
      when Array then '[' + obj.map { |v| stringify(v) }.join(',') + ']'
      when Hash then '{' + obj.map { |k, v| string(k.to_s) + ':' + stringify(v) }.join(',') + '}'
      else raise TypeError, "stringify: unsupported type #{obj.class}"
      end
    end

    # RFC 8785 canonical JSON as produced by canonicalJSON() in ltx-sdk.js:
    # keys sorted by UTF-16 code units, scalars as JSON.stringify.
    def canonical(obj)
      case obj
      when Array then '[' + obj.map { |v| canonical(v) }.join(',') + ']'
      when Hash
        keys = obj.keys.map(&:to_s).sort_by { |k| utf16_units(k) }
        lookup = obj.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
        '{' + keys.map { |k| string(k) + ':' + canonical(lookup[k]) }.join(',') + '}'
      else stringify(obj)
      end
    end

    # UTF-16 code units of s (what JavaScript's charCodeAt iterates). A WTF-8
    # String (lone surrogates as ED A0..BF xx) gives those surrogates as
    # single units; any other invalid byte raises.
    def utf16_units(s)
      s = s.to_s
      return s.encode('UTF-16LE').unpack('v*') if s.valid_encoding?

      bytes = s.b
      units = []
      i = 0
      while i < bytes.bytesize
        b = bytes.getbyte(i)
        len = b < 0x80 ? 1 : b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : 2
        chunk = bytes.byteslice(i, len).force_encoding('UTF-8')
        if chunk.valid_encoding?
          units.concat(chunk.encode('UTF-16LE').unpack('v*'))
        elsif len == 3 && b == 0xED && (0xA0..0xBF).cover?(bytes.getbyte(i + 1).to_i) &&
              (0x80..0xBF).cover?(bytes.getbyte(i + 2).to_i)
          units << (0xD000 | ((bytes.getbyte(i + 1) & 0x3F) << 6) | (bytes.getbyte(i + 2) & 0x3F))
        else
          raise ArgumentError, 'utf16_units: invalid UTF-8 (not WTF-8)'
        end
        i += len
      end
      units
    end

    # String of UTF-16 code units: surrogate pairs joined, a lone surrogate
    # kept as WTF-8 (the String is then not valid UTF-8, as the JS string is
    # not well-formed UTF-16).
    def from_utf16_units(units)
      out = +''.b
      i = 0
      while i < units.size
        u = units[i]
        lo = units[i + 1]
        if (0xD800..0xDBFF).cover?(u) && lo && (0xDC00..0xDFFF).cover?(lo)
          out << (0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)).chr(Encoding::UTF_8).b
          i += 2
          next
        end
        out << if (0xD800..0xDFFF).cover?(u)
                 [0xE0 | (u >> 12), 0x80 | ((u >> 6) & 0x3F), 0x80 | (u & 0x3F)].pack('C*')
               else
                 u.chr(Encoding::UTF_8).b
               end
        i += 1
      end
      out.force_encoding('UTF-8')
    end

    # s.slice(0, n) with JavaScript (UTF-16 code unit) semantics. A cut that
    # splits a surrogate pair keeps the lone high surrogate, as WTF-8
    # (spec/golden/plan-id-prefixes.json planIdWtf8Hex).
    def utf16_slice(s, n)
      from_utf16_units(utf16_units(s)[0, n])
    end
  end
end
