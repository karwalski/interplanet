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
    def string(s)
      JSON.generate(s.to_s)
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

    # UTF-16 code units of s (what JavaScript's charCodeAt iterates).
    def utf16_units(s)
      s.to_s.encode('UTF-16LE').unpack('v*')
    end

    # s.slice(0, n) with JavaScript (UTF-16 code unit) semantics.
    def utf16_slice(s, n)
      units = utf16_units(s)[0, n]
      units.pack('v*').force_encoding('UTF-16LE').encode('UTF-8', invalid: :replace)
    end
  end
end
