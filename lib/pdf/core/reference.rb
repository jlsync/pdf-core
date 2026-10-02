# frozen_string_literal: true

require 'pdf/core/utils'

module PDF
  module Core
    # PDF indirect objects
    #
    # @api private
    class Reference
      # Object identifier
      # @return [Integer]
      attr_accessor :identifier

      # Object generation
      # @return [Integer]
      attr_accessor :gen

      # Object data
      # @return [any]
      attr_accessor :data

      # Offset of the serialized object in the document
      # @return [Integer]
      attr_accessor :offset

      # Object stream
      # @return [Stream]
      def stream
        @stream ||= Stream.new
      end

      attr_writer :stream

      # In PDF only dict object can have a stream attached. This exception
      # indicates someone tried to add a stream to another kind of object.
      class CannotAttachStream < StandardError
        # @param message [String] Error message
        def initialize(message = 'Cannot attach stream to a non-dictionary object')
          super
        end
      end

      # @param id [Integer] Object identifier
      # @param data [any] Object data
      def initialize(id, data)
        @identifier = id
        @gen = 0
        @data = data
        @stream = nil
      end

      # Serialized PDF object
      #
      # @return [String]
      def object
        output = @gen.zero? ? +"#{@identifier} 0 obj\n" : +"#{@identifier} #{@gen} obj\n"
        if @stream.nil? || @stream.empty?
          PDF::Core.append_pdf_object(output, data, false)
          output << "\n"
        else
          PDF::Core.append_pdf_object(output, data.merge(@stream.data), false)
          output << "\n"
          # Append the stream payload straight into the object buffer rather
          # than building "stream\n...\nendstream\n" separately and copying it.
          @stream.write_to(output)
        end

        output << "endobj\n"
      end

      # Appends data to object stream
      #
      # @param io [String] data
      # @return [io]
      # @raise [CannotAttachStream] if object is not a dict
      def <<(io)
        unless @data.is_a?(::Hash)
          raise CannotAttachStream
        end

        (@stream ||= Stream.new) << io
      end

      # Object reference in PDF format
      #
      # @return [String]
      def to_s
        @gen.zero? ? "#{@identifier} 0 R" : "#{@identifier} #{@gen} R"
      end

      # Creates a deep copy of this ref.
      #
      # @param share [Array<Symbol>] a list of dictionary entries to share
      #   between the old ref and the new
      # @return [Reference]
      def deep_copy(share = [])
        r = dup

        case r.data
        when ::Hash
          # Copy each entry not in +share+.
          (r.data.keys - share).each do |k|
            r.data[k] = Utils.deep_clone(r.data[k])
          end
        when PDF::Core::NameTree::Node
          r.data = r.data.deep_copy
        else
          r.data = Utils.deep_clone(r.data)
        end

        r.stream = @stream.nil? ? nil : Utils.deep_clone(@stream)
        r
      end

      # Replaces the data and stream with that of other_ref.
      #
      # @param other_ref [Reference]
      # @return [void]
      def replace(other_ref)
        @data = other_ref.data
        @stream = other_ref.stream
      end
    end
  end
end
