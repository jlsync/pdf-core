# frozen_string_literal: true

require 'zlib'

# prawn/core/stream.rb : Implements Stream objects
#
# Copyright February 2013, Alexander Mankuta.  All Rights Reserved.
#
# This is free software. Please see the LICENSE and COPYING files for details.

module PDF
  module Core
    # PDF Stream object
    class Stream
      # Stream filters
      # @return [PDF::Core::FilterList]
      attr_reader :filters

      # @param io [String] must be mutable
      def initialize(io = nil)
        @filtered_stream = ''
        @stream = io
        @filters = FilterList.new
      end

      # Append data to stream.
      #
      # @param data [String]
      # @return [self]
      def <<(data)
        # Binary and ASCII-compatible ASCII strings can be appended as-is.
        # Other encodings still need a binary copy; never retag the caller's data.
        (@stream ||= ''.b) <<
          if data.encoding == Encoding::BINARY ||
              (data.encoding.ascii_compatible? && data.ascii_only?)
            data
          else
            data.dup.force_encoding(Encoding::BINARY)
          end
        @filtered_stream = nil
        self
      end

      # Set up stream to be compressed when serialized.
      #
      # @param level [Integer, nil] Optional zlib compression level
      #   (e.g., Zlib::BEST_SPEED) to trade size for speed.
      # @return [void]
      def compress!(level: nil)
        unless @filters.include?(:FlateDecode)
          @filtered_stream = nil
          filter =
            if level && level != Zlib::DEFAULT_COMPRESSION
              { FlateDecode: { level: level } }
            else
              :FlateDecode
            end
          @filters << filter
        end
      end

      # Is this stream compressed?
      #
      # @return [Boolean]
      def compressed?
        @filters.include?(:FlateDecode)
      end

      # Is there any data in this stream?
      #
      # @return [Boolean]
      def empty?
        @stream.nil?
      end

      # Stream data with filters applied.
      #
      # @return [Stream]
      def filtered_stream
        return unless @stream

        if @filtered_stream.nil?
          first_filter = @filters.normalized.first&.first
          # FlateDecode.encode reads its input without mutating it and returns a
          # fresh String; other filters (or no filters) need an independent copy
          # so the cached snapshot never aliases @stream.
          encoded = first_filter == :FlateDecode ? @stream : @stream.dup
          @filters.each do |(filter_name, params)|
            filter = PDF::Core::Filters.const_get(filter_name)
            encoded = filter.encode(encoded, params) if filter
          end
          @filtered_stream = encoded.equal?(@stream) ? encoded.dup : encoded
        end

        @filtered_stream
      end

      # Size of data in the stream
      #
      # @return [Integer]
      def length
        @stream.length
      end

      # Serialized stream data
      #
      # @return [String]
      def object
        if filtered_stream
          "stream\n#{filtered_stream}\nendstream\n"
        else
          ''
        end
      end

      # Appends the serialized stream to +output+.
      #
      # Equivalent to `output << object` but without materializing a second
      # copy of the (potentially very large) stream payload.
      #
      # @api private
      # @param output [#<<]
      # @return [void]
      def write_to(output)
        stream = filtered_stream
        return unless stream

        output << "stream\n" << stream << "\nendstream\n"
      end

      # Stream dictionary
      #
      # @return [Hash]
      def data
        if @stream
          fs = filtered_stream
          d = {
            Length: fs.length,
          }
          unless @filters.normalized.empty?
            filter_names = @filters.names
            filter_params = @filters.decode_params
            d[:Filter] = filter_names if filter_names.any?
            d[:DecodeParms] = filter_params if filter_params.any? { |f| !f.nil? }
          end

          d
        else
          {}
        end
      end

      # String representation of the stream for debugging purposes.
      #
      # @return [String]
      def inspect
        format(
          '#<%<class>s:0x%<object_id>014x @stream=%<stream>s, @filters=%<filters>s>',
          class: self.class.name,
          object_id: object_id,
          stream: @stream.inspect,
          filters: @filters.inspect,
        )
      end
    end
  end
end
