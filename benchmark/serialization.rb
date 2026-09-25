# frozen_string_literal: true

# Run with ruby -I/path/to/pdf-core/lib benchmark/serialization.rb.
# For the full render case, run under the application's bundle with PDF_RENDER=1.
require 'pdf/core'
require 'benchmark'
require 'digest'

def measure(label)
  results = 5.times.map do
    GC.start
    before = GC.stat(:total_allocated_objects)
    elapsed = Benchmark.realtime { yield }
    [elapsed, GC.stat(:total_allocated_objects) - before]
  end
  puts format('%s: %.6fs, %d allocations (medians of 5)',
    label, results.map(&:first).sort[2], results.map(&:last).sort[2])
end

measure('200k ASCII appends') do
  stream = PDF::Core::Stream.new
  200_000.times { stream << "q 1 0 0 1 10 20 cm Q\n" }
end

measure('200k integer objects') do
  200_000.times { |i| PDF::Core.pdf_object(i) }
end

if ENV['PDF_RENDER']
  require 'prawn'
  output = nil
  measure('100 pages of badges') do
    pdf = Prawn::Document.new(compress: true, info: {
      CreationDate: Time.utc(2026, 1, 1), ModDate: Time.utc(2026, 1, 1),
    })
    100.times do |page|
      pdf.start_new_page unless page.zero?
      10.times do |row|
        pdf.stroke_rectangle([10, 720 - row * 65], 450, 55)
        pdf.draw_text("Badge #{page * 10 + row}: Alexander Example", at: [20, 690 - row * 65])
      end
    end
    output = pdf.render
  end
  puts "PDF bytes: #{output.bytesize}; SHA256: #{Digest::SHA256.hexdigest(output)}"
end
