# frozen_string_literal: true

module PDF
  module Core
    module_function

    # Serializes floating number into a string
    #
    # @param num [Numeric]
    # @return [String]
    def real(num)
      # Fast path for integral values, which are very common in content
      # streams. Float#to_s gives the same "N.0" (or "-0.0") form as the
      # general path below for magnitudes where it doesn't use an exponent.
      if num.is_a?(Integer)
        return "#{num}.0"
      elsif num.is_a?(Float) && num.abs < 1e15 && num == num.truncate
        return num.to_s
      elsif num.is_a?(Float) && num.abs < 1e10
        # Most content stream coordinates have few decimals, and are exactly
        # representable at the 5 decimals that '%.5f' rounds to. When that
        # holds the value can be rendered from its scaled integer, which skips
        # `format` entirely: measured ~24% faster and 5x fewer allocated bytes
        # than the general path below.
        scaled = scaled_five_decimals(num)
        if scaled && scaled.abs >= 100_000
          result = scaled.to_s
          result.insert(result.length - 5, '.')
          strip_trailing_zeroes!(result)
          return result
        end
      end

      result = format('%.5f', num)
      strip_trailing_zeroes!(result)
      result
    end

    # Returns +num+ scaled by 100_000 when that round trip is exact, otherwise
    # nil.
    #
    # @api private
    # @param num [Float]
    # @return [Integer, nil]
    def scaled_five_decimals(num)
      scaled = (num * 100_000).round
      # Float equality is deliberate here: this *is* the test that rounding to
      # five decimals did not move the value, which is what makes it safe to
      # serialize from the integer.
      # rubocop:disable Lint/FloatComparison
      return scaled if scaled.fdiv(100_000) == num
      # rubocop:enable Lint/FloatComparison

      nil
    end

    # Drops trailing zeroes from a serialized number, keeping at least one digit
    # after the decimal point.
    #
    # Mutates in place: the previous `result[len..] = ''` allocated a Range
    # object on every single call, which showed up as the largest single source
    # of Range allocations in a profiled render.
    #
    # @api private
    # @param result [String]
    # @return [String] +result+
    def strip_trailing_zeroes!(result)
      result.chop! while result.getbyte(result.length - 1) == 48 && result.getbyte(result.length - 2) != 46 # '0', '.'
      result
    end

    # Pre-encoded UTF-16BE byte order mark
    # @api private
    UTF16BE_BOM = "\xFE\xFF".b.force_encoding(::Encoding::UTF_16BE).freeze

    # Serializes a n array of numbers. This is specifically for use in PDF
    # content streams.
    #
    # @param array [Array<Numeric>]
    # @return [String]
    def real_params(array)
      return '' if array.empty?

      out = +''
      first = true
      array.each do |e|
        if first
          first = false
        else
          out << ' '
        end
        out << real(e)
      end
      out
    end

    # Converts string to UTF-16BE encoding as expected by PDF.
    #
    # @param str [String]
    # @return [String]
    # @api private
    def utf8_to_utf16(str)
      UTF16BE_BOM + str.encode(::Encoding::UTF_16BE)
    end

    # Encodes any string into a hex representation. The result is a string
    # with only 0-9 and a-f characters. That result is valid ASCII so tag
    # it as such to account for behaviour of different ruby VMs.
    #
    # @param str [String]
    # @return [String]
    def string_to_hex(str)
      str.unpack1('H*').force_encoding(::Encoding::US_ASCII)
    end

    # Characters to escape in name objects
    # @api private
    ESCAPED_NAME_CHARACTERS = ((1..32).to_a + [35, 40, 41, 47, 60, 62] + (127..255).to_a).to_set.freeze

    # Maximum entries in the symbol serialization cache to bound memory growth
    # @api private
    SYMBOL_CACHE_LIMIT = 500

    # How to escape special characters in literal strings
    # @api private
    STRING_ESCAPE_MAP = { '(' => '\(', ')' => '\)', '\\' => '\\\\', "\r" => '\r' }.freeze

    # Serializes Ruby objects to their PDF equivalents.  Most primitive objects
    # will work as expected, but please note that Name objects are represented
    # by Ruby Symbol objects and Dictionary objects are represented by Ruby
    # hashes (keyed by symbols)
    #
    # Examples:
    #
    #     pdf_object(true)      #=> "true"
    #     pdf_object(false)     #=> "false"
    #     pdf_object(1.2124)    #=> "1.2124"
    #     pdf_object('foo bar') #=> "(foo bar)"
    #     pdf_object(:Symbol)   #=> "/Symbol"
    #     pdf_object(['foo',:bar, [1,2]]) #=> "[foo /bar [1 2]]"
    #
    # @param obj [nil, Boolean, Numeric, Array, Hash, Time, Symbol, String,
    #   PDF::Core::ByteString, PDF::Core::LiteralString,
    #   PDF::Core::NameTree::Node, PDF::Core::NameTree::Value,
    #   PDF::Core::OutlineRoot, PDF::Core::OutlineItem, PDF::Core::Reference]
    #   Object to serialise
    # @param in_content_stream [Boolean] Specifies whether to use content stream
    #   format or object format
    # @return [String]
    # @raise [PDF::Core::Errors::FailedObjectConversion]
    def pdf_object(obj, in_content_stream = false)
      # Single-token scalars are serialized straight to their own string.
      # Routing them through the buffer below would allocate one extra String
      # per call for no benefit.
      case obj
      when Integer, PDF::Core::Reference
        return obj.to_s
      when Numeric
        num_string = real(obj)
        num_string.chomp!('.0')
        return num_string
      when NilClass
        return 'null'
      when TrueClass
        return 'true'
      when FalseClass
        return 'false'
      end

      out = +''
      append_pdf_object(out, obj, in_content_stream)
      out
    end

    # Appends the PDF serialization of +obj+ to the +out+ buffer.
    #
    # This is the recursive worker behind {pdf_object}. Writing straight into
    # the caller's buffer avoids allocating (and then copying) an intermediate
    # string for every nested array and dictionary.
    #
    # @api private
    # @param out [String] buffer to append to
    # @param obj [any] object to serialize, as accepted by {pdf_object}
    # @param in_content_stream [Boolean] content stream or object format
    # @return [String] +out+
    def append_pdf_object(out, obj, in_content_stream)
      # Fast path for the classes that dominate serialization: content stream
      # strings and coordinates, plus dictionary/array structure. A plain
      # `case` costs one `is_a?` per branch, and a String has to walk seven
      # branches to reach `when String`.
      #
      # These are exact class checks on purpose. Subclasses -- including
      # ActiveSupport::SafeBuffer and pdf-core's own LiteralString/ByteString,
      # which must be handled *before* String -- fall through to the full case
      # below, so their specialised handling is untouched.
      klass = obj.class

      if klass.equal?(::String)
        obj = utf8_to_utf16(obj) unless in_content_stream
        return out << '<' << string_to_hex(obj) << '>'
      elsif klass.equal?(::Integer)
        return out << obj.to_s
      elsif klass.equal?(::Float)
        num_string = real(obj)
        num_string.chomp!('.0')
        return out << num_string
      elsif klass.equal?(::Hash)
        append_pdf_dictionary(out, obj, in_content_stream)
        return out
      elsif klass.equal?(::Array)
        append_pdf_array(out, obj, in_content_stream)
        return out
      end

      case obj
      when Symbol
        append_pdf_name(out, obj)
      when Integer, PDF::Core::Reference
        out << obj.to_s
      when ::Hash
        append_pdf_dictionary(out, obj, in_content_stream)
      when Array
        append_pdf_array(out, obj, in_content_stream)
      when PDF::Core::LiteralString
        out << '(' << obj.gsub(/[\\\r()]/, STRING_ESCAPE_MAP) << ')'
      when PDF::Core::ByteString
        out << '<' << obj.unpack1('H*') << '>'
      when String
        obj = utf8_to_utf16(obj) unless in_content_stream
        out << '<' << string_to_hex(obj) << '>'
      when Numeric
        num_string = real(obj)
        # `real` always returns a freshly allocated string here, so the
        # redundant ".0" suffix is dropped in place rather than by allocating
        # a copy with String#[].
        num_string.chomp!('.0')
        out << num_string
      when NilClass
        out << 'null'
      when TrueClass
        out << 'true'
      when FalseClass
        out << 'false'
      when Time
        obj = "#{obj.strftime('D:%Y%m%d%H%M%S%z').chop.chop}'00'"
        out << '(' << obj.gsub(/[\\\r()]/, STRING_ESCAPE_MAP) << ')'
      when PDF::Core::NameTree::Node, PDF::Core::OutlineRoot, PDF::Core::OutlineItem
        append_pdf_object(out, obj.to_hash, false)
      when PDF::Core::NameTree::Value
        append_pdf_object(out, obj.name, false)
        out << ' '
        append_pdf_object(out, obj.value, false)
      else
        raise PDF::Core::Errors::FailedObjectConversion,
          "This object cannot be serialized to PDF (#{obj.inspect})"
      end

      out
    end

    # Appends a PDF name object (the serialization of a Symbol).
    #
    # @api private
    # @param out [String] buffer to append to
    # @param name [Symbol]
    # @return [String] +out+
    def append_pdf_name(out, name)
      cache = (@symbol_str_cache ||= {})
      cached = cache[name]

      unless cached
        cache.shift if cache.size >= SYMBOL_CACHE_LIMIT
        string = name.to_s
        cached = +'/'
        string.each_byte do |n|
          if ESCAPED_NAME_CHARACTERS.include?(n)
            cached << '#' << n.to_s(16).upcase
          else
            cached << n
          end
        end
        cache[name] = cached.freeze
      end

      out << cached
    end

    # Appends a PDF array.
    #
    # @api private
    # @param out [String] buffer to append to
    # @param array [Array]
    # @param in_content_stream [Boolean]
    # @return [String] +out+
    def append_pdf_array(out, array, in_content_stream)
      out << '['
      first = true
      array.each do |e|
        if first
          first = false
        else
          out << ' '
        end
        append_pdf_object(out, e, in_content_stream)
      end
      out << ']'
    end

    # Appends a PDF dictionary.
    #
    # @api private
    # @param out [String] buffer to append to
    # @param hash [Hash]
    # @param in_content_stream [Boolean]
    # @return [String] +out+
    def append_pdf_dictionary(out, hash, in_content_stream)
      out << '<< '
      keys = hash.keys
      begin
        keys.sort!
      rescue ArgumentError
        keys.sort_by!(&:to_s)
      end

      keys.each do |k|
        unless k.is_a?(String) || k.is_a?(Symbol)
          raise PDF::Core::Errors::FailedObjectConversion,
            'A PDF Dictionary must be keyed by names'
        end
        append_pdf_object(out, k.is_a?(Symbol) ? k : k.to_sym, in_content_stream)
        out << ' '
        append_pdf_object(out, hash[k], in_content_stream)
        out << "\n"
      end
      out << '>>'
    end
  end
end
