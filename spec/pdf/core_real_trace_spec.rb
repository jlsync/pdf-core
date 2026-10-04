# frozen_string_literal: true

require 'spec_helper'
require 'pdf/core/real_trace'
require 'stringio'

RSpec.describe PDF::Core::RealTrace do
  # The exit-time report is noise in a spec run.
  RSpec.configure do |config|
    config.after(:suite) { PDF::Core::RealTrace.enabled = false }
  end

  before { described_class.reset }

  after { described_class.reset }

  def report
    io = StringIO.new
    described_class.report(io)
    io.string
  end

  it 'records each call under the path real() will take' do
    PDF::Core.real(1) # integer
    PDF::Core.real(1.0) # integral float
    PDF::Core.real(1.5) # integer fast path
    PDF::Core.real(0.1234567890123) # needs format('%.5f')

    text = report
    expect(text).to include('calls: 4')
    expect(text).to match(/integer\s+1$/)
    expect(text).to match(/integral_float\s+1$/)
    expect(text).to match(/scaled\s+1$/)
    expect(text).to match(/format\s+1$/)
  end

  it 'records non-finite values, which also reach the fallback path' do
    expect(PDF::Core.real(Float::NAN)).to eq('NaN')
    expect(PDF::Core.real(Float::INFINITY)).to eq('Inf')

    text = report
    expect(text).to include('calls: 2')
    expect(text).to match(/format\s+2$/)
  end

  it 'reports distinct values against total calls for the fallback path' do
    PDF::Core.real(0.1234567890123)
    3.times { PDF::Core.real(0.9876543210987) }

    expect(report).to match(/format\s+2 distinct of\s+4 calls\s+\(50\.0%\)/)
  end

  it 'leaves serialization unchanged' do
    expect(PDF::Core.real(1)).to eq('1.0')
    expect(PDF::Core.real(1.5)).to eq('1.5')
    expect(PDF::Core.real(0.1234567890123)).to eq('0.12346')
  end

  it 'stops recording once disabled' do
    described_class.enabled = false
    PDF::Core.real(1.5)

    expect(report).to include('calls: 0')
  end
end
