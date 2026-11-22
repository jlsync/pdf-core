# frozen_string_literal: true

module PDF
  module Core
    module_function

    # Lower and upper bounds for precomputed frozen integer strings (covering
    # common kerning offsets, coordinates, font sizes, line widths, and IDs).
    # @api private
    SMALL_INT_MIN = -128
    # @api private
    SMALL_INT_MAX = 1024

    # Precomputed frozen integer representations for PDF objects.
    # @api private
    SMALL_INTS = (SMALL_INT_MIN..SMALL_INT_MAX).map { |i| i.to_s.freeze }.freeze

    # Precomputed frozen real representations for common non-negative integers.
    # @api private
    SMALL_INT_REALS = Array.new(SMALL_INT_MAX + 1) { |i| "#{i}.0".freeze }.freeze

    # Serializes floating number into a string
    #
    # @param num [Numeric]
    # @return [String]
    def real(num)
      if num.is_a?(Integer)
        # rubocop:disable Style/ComparableBetween -- inline comparisons avoid Comparable#between?
        return SMALL_INT_REALS[num].dup if num >= 0 && num <= SMALL_INT_MAX
        # rubocop:enable Style/ComparableBetween

        return num.to_s << '.0'
      elsif num.is_a?(Float)
        if num.zero?
          return +(num.equal?(0.0) || (1.0 / num).positive? ? '0.0' : '-0.0')
        end

        return cached_formatted_real(num).dup
      end

      formatted_real(num)
    end

    # Appends the PDF real serialization of +num+ directly to +out+.
    #
    # Avoids duplicating cached strings or allocating for small integers and
    # repeated floats when the caller only needs to copy digits into a buffer.
    #
    # @api private
    # @param out [String] buffer to append to
    # @param num [Numeric]
    # @return [String] +out+
    def append_real(out, num)
      if num.is_a?(Integer)
        # rubocop:disable Style/ComparableBetween -- inline comparisons avoid Comparable#between?
        return out << SMALL_INT_REALS[num] if num >= 0 && num <= SMALL_INT_MAX
        # rubocop:enable Style/ComparableBetween

        return out << num.to_s << '.0'
      elsif num.is_a?(Float)
        if num.zero?
          return out << (num.equal?(0.0) || (1.0 / num).positive? ? '0.0' : '-0.0')
        end

        return out << cached_formatted_real(num)
      end

      out << formatted_real(num)
    end

    # Looks up or computes the frozen formatted representation of a non-zero
    # Float in the bounded number cache.
    #
    # Content streams reuse coordinates, dimensions, and color values heavily,
    # so checking the cache before formatting lets append_real and
    # append_pdf_float write repeated floats with zero allocations.
    #
    # Only non-zero Floats are cached. Signed zeroes (0.0 and -0.0) hash equal
    # and are handled before reaching this method. Other Numerics (e.g.
    # Complex(0.0, 0) vs Complex(-0.0, 0)) also hash equal while formatting
    # differently, so they bypass the cache. NaN is never equal to itself so it
    # is formatted without being stored.
    #
    # @api private
    # @param num [Float]
    # @return [String] frozen formatted number
    def cached_formatted_real(num)
      cache = (@real_str_cache ||= {})
      cached = cache[num]
      unless cached
        cached = num.abs < 1e15 && num == num.truncate ? num.to_s : formatted_real(num)
        unless num.nan?
          cache.clear if cache.size >= REAL_CACHE_LIMIT
          cache[num] = cached.freeze
        end
      end
      cached
    end

    # Renders +num+ the general way: five decimal places, trailing zeroes
    # trimmed.
    #
    # @api private
    # @param num [Numeric]
    # @return [String]
    def formatted_real(num)
      result = format('%.5f', num)
      strip_trailing_zeroes!(result)
      result
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
        append_real(out, e)
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

    # ASCII characters that require hex-escaping in PDF name objects
    # @api private
    NAME_ESCAPE_RE = %r{[\x01-\x20#()/<>\x7f]}

    # Maximum entries in the symbol serialization cache to bound memory growth
    # @api private
    SYMBOL_CACHE_LIMIT = 500

    # Maximum entries in the serialized-number cache. Sized to hold the
    # distinct values of a whole document (measured ~800 for a table-heavy
    # report) with room for the next one, since a server renders many.
    # @api private
    REAL_CACHE_LIMIT = 2048

    # How to escape special characters in literal strings
    # @api private
    STRING_ESCAPE_MAP = { '(' => '\(', ')' => '\)', '\\' => '\\\\', "\r" => '\r' }.freeze

    # Characters that require escaping in PDF literal strings
    # @api private
    LITERAL_ESCAPE_RE = /[\\\r()]/

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
      when Symbol
        return cached_pdf_name(obj).dup
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
      case obj
      when Symbol
        out << cached_pdf_name(obj)
      when Integer
        # rubocop:disable Style/ComparableBetween -- inline comparisons avoid Comparable#between?
        out <<
          if obj >= SMALL_INT_MIN && obj <= SMALL_INT_MAX
            SMALL_INTS[obj - SMALL_INT_MIN]
          else
            obj.to_s
          end
        # rubocop:enable Style/ComparableBetween
      when PDF::Core::Reference
        out << obj.to_s
      when PDF::Core::ByteString
        out << '<' << obj.unpack1('H*') << '>'
      when PDF::Core::LiteralString
        append_literal_string(out, obj)
      when String
        if in_content_stream
          out << '<' << obj.unpack1('H*') << '>'
        else
          out << '<feff' << obj.encode(::Encoding::UTF_16BE).unpack1('H*') << '>'
        end
      when Numeric
        append_pdf_float(out, obj)
      when Array
        append_pdf_array(out, obj, in_content_stream)
      when ::Hash
        append_pdf_dictionary(out, obj, in_content_stream)
      when NilClass
        out << 'null'
      when TrueClass
        out << 'true'
      when FalseClass
        out << 'false'
      when Time
        obj = "#{obj.strftime('D:%Y%m%d%H%M%S%z').chop.chop}'00'"
        out << '(' << obj.gsub(LITERAL_ESCAPE_RE, STRING_ESCAPE_MAP) << ')'
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

    # Appends a PDF numeric value, stripping any redundant '.0' suffix.
    #
    # @api private
    # @param out [String] buffer to append to
    # @param num [Numeric]
    # @return [String] +out+
    def append_pdf_float(out, num)
      if num.is_a?(Float)
        if num.zero?
          return out << (num.equal?(0.0) || (1.0 / num).positive? ? '0' : '-0')
        end

        str = cached_formatted_real(num)
        # Cached strings end in '.0' for integral floats or when rounding
        # bumped an input to an integer; slice off the suffix without mutating
        # the cache.
        return out << (str.end_with?('.0') ? str.byteslice(0, str.bytesize - 2) : str)
      end

      str = formatted_real(num)
      str.chomp!('.0')
      out << str
    end

    # Appends a PDF literal string, skipping gsub when no characters need escaping.
    #
    # @api private
    # @param out [String] buffer to append to
    # @param str [String]
    # @return [String] +out+
    def append_literal_string(out, str)
      escaped = str.match?(LITERAL_ESCAPE_RE) ? str.gsub(LITERAL_ESCAPE_RE, STRING_ESCAPE_MAP) : str
      out << '(' << escaped << ')'
    end

    # Appends a PDF name object (the serialization of a Symbol).
    #
    # @api private
    # @param out [String] buffer to append to
    # @param name [Symbol]
    # @return [String] +out+
    def append_pdf_name(out, name)
      out << cached_pdf_name(name)
    end

    # Looks up or computes the frozen PDF name representation of a Symbol.
    #
    # @api private
    # @param name [Symbol]
    # @return [String] frozen PDF name
    def cached_pdf_name(name)
      cache = (@symbol_str_cache ||= {})
      cached = cache[name]

      unless cached
        cache.shift if cache.size >= SYMBOL_CACHE_LIMIT
        string = name.name
        cached =
          if string.ascii_only? && !string.match?(NAME_ESCAPE_RE)
            "/#{string}".freeze
          else
            buf = +'/'
            string.each_byte do |n|
              if ESCAPED_NAME_CHARACTERS.include?(n)
                buf << '#' << n.to_s(16).upcase
              else
                buf << n
              end
            end
            buf.freeze
          end
        cache[name] = cached
      end

      cached
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
      if hash.size <= 1
        hash.each { |k, v| append_pdf_dictionary_entry(out, k, v, in_content_stream) }
      else
        keys = hash.keys
        begin
          keys.sort!
        rescue ArgumentError
          keys.sort_by!(&:to_s)
        end

        keys.each { |k| append_pdf_dictionary_entry(out, k, hash[k], in_content_stream) }
      end
      out << '>>'
    end

    # Appends a single key-value entry to a PDF dictionary.
    #
    # @api private
    # @param out [String] buffer to append to
    # @param key [Symbol, String]
    # @param value [any]
    # @param in_content_stream [Boolean]
    # @return [String] +out+
    def append_pdf_dictionary_entry(out, key, value, in_content_stream)
      sym =
        if key.is_a?(Symbol)
          key
        elsif key.is_a?(String)
          key.to_sym
        else
          raise PDF::Core::Errors::FailedObjectConversion,
            'A PDF Dictionary must be keyed by names'
        end
      out << cached_pdf_name(sym) << ' '
      append_pdf_object(out, value, in_content_stream)
      out << "\n"
    end
  end
end
