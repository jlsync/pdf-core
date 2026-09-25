# frozen_string_literal: true

require 'set'

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
      end

      result = format('%.5f', num)
      # Strip trailing zeroes but keep at least one digit after the point.
      # Equivalent to `sub!(/((?<!\.)0)+\z/, '')` without the regex.
      len = result.length
      len -= 1 while result.getbyte(len - 1) == 48 && result.getbyte(len - 2) != 46 # '0', '.'
      result[len..] = '' if len < result.length
      result
    end

    # Serializes a n array of numbers. This is specifically for use in PDF
    # content streams.
    #
    # @param array [Array<Numeric>]
    # @return [String]
    def real_params(array)
      array.map { |e| real(e) }.join(' ')
    end

    # Converts string to UTF-16BE encoding as expected by PDF.
    #
    # @param str [String]
    # @return [String]
    # @api private
    def utf8_to_utf16(str)
      (+"\xFE\xFF").force_encoding(::Encoding::UTF_16BE) <<
        str.encode(::Encoding::UTF_16BE)
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
      case obj
      when NilClass then 'null'
      when TrueClass then 'true'
      when FalseClass then 'false'
      when Integer then String(obj)
      when Numeric
        num_string = real(obj)

        # Truncate trailing fraction zeroes. `real` already strips all but a
        # lone "0" after the point, so only an "N.0" suffix remains to drop.
        num_string.end_with?('.0') ? num_string[0...-2] : num_string
      when Array
        # Build array serialization without intermediate arrays
        out = +'['
        last_index = obj.length - 1
        obj.each_with_index do |e, i|
          out << pdf_object(e, in_content_stream)
          out << ' ' if i < last_index
        end
        out << ']'
        out
      when PDF::Core::LiteralString
        obj = obj.gsub(/[\\\r()]/, STRING_ESCAPE_MAP)
        "(#{obj})"
      when Time
        obj = "#{obj.strftime('D:%Y%m%d%H%M%S%z').chop.chop}'00'"
        obj = obj.gsub(/[\\\r()]/, STRING_ESCAPE_MAP)
        "(#{obj})"
      when PDF::Core::ByteString
        "<#{obj.unpack1('H*')}>"
      when String
        obj = utf8_to_utf16(obj) unless in_content_stream
        "<#{string_to_hex(obj)}>"
      when Symbol
        (@symbol_str_cache ||= {})[obj] ||=
          begin
            s = obj.to_s
            out = +'/'
            s.each_byte do |n|
              if ESCAPED_NAME_CHARACTERS.include?(n)
                out << '#' << n.to_s(16).upcase
              else
                out << n
              end
            end
            out
          end
      when ::Hash
        output = +'<< '
        obj
          .sort_by { |k, _v| k.to_s }
          .each do |(k, v)|
            unless k.is_a?(String) || k.is_a?(Symbol)
              raise PDF::Core::Errors::FailedObjectConversion,
                'A PDF Dictionary must be keyed by names'
            end
            output << pdf_object(k.to_sym, in_content_stream) << ' ' <<
              pdf_object(v, in_content_stream) << "\n"
          end
        output << '>>'
      when PDF::Core::Reference
        obj.to_s
      when PDF::Core::NameTree::Node, PDF::Core::OutlineRoot, PDF::Core::OutlineItem
        pdf_object(obj.to_hash)
      when PDF::Core::NameTree::Value
        "#{pdf_object(obj.name)} #{pdf_object(obj.value)}"
      else
        raise PDF::Core::Errors::FailedObjectConversion,
          "This object cannot be serialized to PDF (#{obj.inspect})"
      end
    end
  end
end
