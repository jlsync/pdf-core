# frozen_string_literal: true

require 'zlib'

module PDF
  module Core
    # Stream filters
    module Filters
      # zlib/deflate compression
      module FlateDecode
        # zlib level used for page content streams.
        #
        # Content streams are highly repetitive (text operators, coordinates),
        # so Zlib::BEST_SPEED compresses them roughly 2.6x faster than this
        # level for around 16% more bytes. Compression is only a small share of
        # a typical render, though (measured well under 1% end to end), so the
        # default level is kept here and the trade is not worth taking.
        #
        # @return [Integer]
        CONTENT_STREAM_LEVEL = Zlib::DEFAULT_COMPRESSION

        # Encode stream data
        #
        # @param stream [String] stream data
        # @param params [Hash, nil] optional parameters, e.g. { level: Zlib::BEST_SPEED }
        # @return [String]
        def self.encode(stream, params = nil)
          if params && (level = params[:level])
            # Allow callers to trade size for speed via compression level
            Zlib::Deflate.deflate(stream, level)
          else
            Zlib::Deflate.deflate(stream)
          end
        end

        # Decode stream data
        #
        # @param stream [String] stream data
        # @param _params [nil] unused, here for API compatibility
        # @return [String]
        def self.decode(stream, _params = nil)
          Zlib::Inflate.inflate(stream)
        end
      end

      # Data encoding using DCT (discrete cosine transform) technique based on
      # the JPEG standard.
      #
      # Pass through stub.
      module DCTDecode
        # Encode stream data
        #
        # @param stream [String] stream data
        # @param _params [nil] unused, here for API compatibility
        # @return [String]
        def self.encode(stream, _params = nil)
          stream
        end

        # Decode stream data
        #
        # @param stream [String] stream data
        # @param _params [nil] unused, here for API compatibility
        # @return [String]
        def self.decode(stream, _params = nil)
          stream
        end
      end
    end
  end
end
