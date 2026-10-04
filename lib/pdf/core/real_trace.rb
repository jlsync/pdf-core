# frozen_string_literal: true

module PDF
  # Reopened to hold number-serialization diagnostics; the namespace itself is
  # documented in lib/pdf/core.rb.
  module Core
    # Diagnostic instrumentation for {PDF::Core.real}.
    #
    # `real` is the number serialization hot spot, and the question that decides
    # whether it can be made cheaper is how much of its input *repeats*.
    # Repeated values are the only ones a cache could skip: the remaining
    # `format('%.5f')` calls cannot be replaced with integer arithmetic without
    # changing the rounding, so the exactness test stays.
    #
    # Nothing in pdf-core requires this file. Enable it explicitly with
    #
    #   require 'pdf/core/real_trace'
    #
    # and it reports to stderr at process exit. Set PDF_CORE_REAL_TRACE_FILE to
    # append the report to a file instead, which is easier to collect from a
    # server. While it is enabled, timings from the process are not meaningful,
    # because measuring costs work on every call.
    #
    # @api private
    module RealTrace
      # Bounds the distinct-value sets so a long-running process cannot grow
      # without limit while measuring.
      DISTINCT_LIMIT = Integer(ENV.fetch('PDF_CORE_REAL_TRACE_LIMIT', '1000000'))

      # How many of the most repeated values to list.
      TOP_REPEATED = 15

      # Values of |num| at or above this magnitude are outside the integer fast
      # path, so they always reach `format`.
      MAGNITUDE_LIMIT = 1e10

      # Order used when reporting call counts.
      CALL_PATHS = %i[integer integral_float scaled format other].freeze

      class << self
        # Whether calls are currently being recorded.
        attr_accessor :enabled

        # Clears all collected data and starts recording.
        #
        # @return [void]
        def reset
          @calls = Hash.new(0)
          @distinct = Hash.new { |hash, key| hash[key] = {} }
          # magnitude band => calls, both for the format path and for all floats
          @bands = Hash.new(0)
          @bands_all = Hash.new(0)
          @overflowed = false
          @enabled = true
          nil
        end

        # Records one call to {PDF::Core.real}.
        #
        # @param num [Object] the value being serialized
        # @return [void]
        def record(num)
          return unless @enabled

          path = classify(num)
          @calls[path] += 1
          return unless num.is_a?(Float)

          band = magnitude_band(num)
          if band
            @bands_all[band] += 1
            @bands[band] += 1 if path == :format
          end
          note_distinct(path, num)
        end

        # Writes the collected report. Called automatically at exit, and also
        # callable directly to snapshot a running process.
        #
        # @param io [#puts]
        # @return [void]
        def report(io = $stderr)
          io.puts('PDF::Core.real trace')
          io.puts("  calls: #{@calls.values.sum}")
          CALL_PATHS.each { |path| report_calls(io, path) }
          report_distinct(io)
          report_bands(io)
          report_repeated(io)
          io.flush if io.respond_to?(:flush)
          nil
        end

        private

        # Adds `num` to the distinct-value set for `path`, or counts another
        # sighting of it. The set is capped so measurement cannot grow without
        # limit.
        #
        # @return [void]
        def note_distinct(path, num)
          seen = @distinct[path]
          if seen.key?(num)
            seen[num] += 1
          elsif seen.size < DISTINCT_LIMIT
            seen[num] = 1
          else
            @overflowed = true
          end
        end

        # @return [void]
        def report_calls(io, path)
          count = @calls[path]
          return if count.zero?

          io.puts("    #{path.to_s.ljust(16)}#{count.to_s.rjust(10)}")
        end

        # @return [void]
        def report_distinct(io)
          io.puts('  distinct float inputs (cache potential):')
          %i[scaled format].each do |path|
            calls = @calls[path]
            next if calls.zero?

            distinct = @distinct[path].size
            percent = (Float(distinct) / calls * 100).round(2)
            label = path.to_s.ljust(8)
            counts = "#{distinct.to_s.rjust(8)} distinct of #{calls.to_s.rjust(8)} calls"
            io.puts("    #{label}#{counts}  (#{percent}%)")
          end
          note = @overflowed ? 'CAP HIT, totals are lower bounds' : 'not hit'
          io.puts("    (value sets capped at #{DISTINCT_LIMIT}; #{note})")
        end

        # @return [void]
        def report_bands(io)
          io.puts('  magnitude band (log10|value|): all float calls / format-path')
          (@bands_all.keys | @bands.keys).sort.each do |band|
            label = band.to_s.rjust(5)
            counts = "#{@bands_all[band].to_s.rjust(10)} / #{@bands[band].to_s.rjust(10)}"
            io.puts("    #{label}  #{counts}")
          end
        end

        # @return [void]
        def report_repeated(io)
          io.puts('  most repeated format-path values (value x count):')
          top = @distinct[:format].sort_by { |_value, count| -count }.first(TOP_REPEATED)
          if top.empty?
            io.puts('    (none)')
          else
            top.each { |value, count| io.puts("    #{value.inspect.ljust(24)} x #{count}") }
          end
        end

        # Mirrors the branch structure of PDF::Core.real so calls can be
        # attributed to a path. Only the split between paths depends on this;
        # the totals and distinct counts do not.
        #
        # @return [Symbol]
        def classify(num)
          return :integer if num.is_a?(Integer)
          return :other unless num.is_a?(Float)
          # NaN and the infinities compare false against everything, so real()
          # skips every fast path and reaches format.
          return :format unless num.finite?
          return :integral_float if num.abs < 1e15 && num == num.truncate
          return :format if num.abs >= MAGNITUDE_LIMIT

          classify_scaled(num)
        end

        # @return [Symbol]
        def classify_scaled(num)
          scaled = (num * 100_000).round
          # rubocop:disable Lint/FloatComparison
          scaled.fdiv(100_000) == num ? :scaled : :format
          # rubocop:enable Lint/FloatComparison
        end

        # Magnitude band of `num`, or nil for values that have no magnitude
        # (NaN and the infinities).
        #
        # @return [Integer, nil]
        def magnitude_band(num)
          return 0 if num.zero?
          return unless num.finite?

          Math.log10(num.abs).floor
        end
      end

      reset
    end

    # Wraps the module-level `real` so that every call is recorded.
    module RealTraceHook
      # Records the argument, then serializes as usual.
      #
      # @return [String]
      def real(num)
        RealTrace.record(num)
        super
      end
    end

    singleton_class.prepend(RealTraceHook)

    at_exit do
      next unless RealTrace.enabled

      path = ENV.fetch('PDF_CORE_REAL_TRACE_FILE', nil)
      if path
        File.open(path, 'a') { |file| RealTrace.report(file) }
      else
        RealTrace.report($stderr)
      end
    end
  end
end
