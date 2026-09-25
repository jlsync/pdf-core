# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PDF::Core::Stream do
  subject(:stream) { described_class.new }

  it 'compresses a stream upon request' do
    stream << ('Hi There ' * 20)

    cstream = described_class.new
    cstream << ('Hi There ' * 20)
    cstream.compress!

    expect(cstream.filtered_stream.length).to be < stream.length
    expect(cstream.data[:Filter]).to eq [:FlateDecode]
  end

  it 'exposes compression state' do
    stream << 'Hello'
    stream.compress!

    expect(stream).to be_compressed
  end

  it 'detects from filters if stream is compressed' do
    stream << 'Hello'
    stream.filters << :FlateDecode

    expect(stream).to be_compressed
  end

  it 'has Length if in data' do
    stream << 'hello'

    expect(stream.data[:Length]).to eq 5
  end

  it 'updates Length when updated' do
    stream << 'hello'
    expect(stream.data[:Length]).to eq 5

    stream << ' world'
    expect(stream.data[:Length]).to eq 11
  end

  it 'correctly handles decode params' do
    stream << 'Hello'
    stream.filters << { FlateDecode: { Predictor: 15 } }

    expect(stream.data[:DecodeParms]).to eq [{ Predictor: 15 }]
  end

  it 'handles multibyte encoded strings correctly' do
    stream << '♥'

    expect(stream.data[:Length]).to eq 3
  end

  it 'appends mixed encodings as bytes without changing caller strings' do
    inputs = ['plain', '♥', "\xFF".b, 'hello'.encode('UTF-16BE')]
    inputs.each(&:freeze)
    encodings = inputs.map(&:encoding)

    inputs.each { |input| stream << input }

    expect(stream.filtered_stream).to eq inputs.map(&:b).join
    expect(stream.filtered_stream.encoding).to eq Encoding::BINARY
    expect(stream.data[:Length]).to eq inputs.sum(&:bytesize)
    expect(inputs.map(&:encoding)).to eq encodings
  end

  it 'copies appended data independently of later caller mutations' do
    input = +'plain'
    stream << input
    input.replace('changed')

    expect(stream.filtered_stream).to eq 'plain'
  end

  it 'keeps an unfiltered snapshot independent of later appends' do
    stream << 'first'
    snapshot = stream.filtered_stream
    stream << 'second'

    expect(snapshot).to eq 'first'
    expect(stream.filtered_stream).to eq 'firstsecond'
  end

  it 'does not let changes to a filtered snapshot corrupt the source' do
    stream << 'first'
    stream.filtered_stream.replace('changed')
    stream.compress!

    expect(Zlib::Inflate.inflate(stream.filtered_stream)).to eq 'first'
  end

  it 'recompresses after appending more bytes' do
    stream << 'first'
    stream.compress!
    expect(Zlib::Inflate.inflate(stream.filtered_stream)).to eq 'first'

    stream << '♥'
    expect(Zlib::Inflate.inflate(stream.filtered_stream)).to eq 'first♥'.b
    expect(stream.data[:Length]).to eq stream.filtered_stream.bytesize
  end

  it 'uses encoder compression levels without writing them into DecodeParms' do
    [Zlib::NO_COMPRESSION, Zlib::BEST_SPEED, Zlib::BEST_COMPRESSION].each do |level|
      compressed = described_class.new
      compressed << ('Hello ' * 100)
      compressed.compress!(level: level)

      expect(compressed.filtered_stream).to eq Zlib::Deflate.deflate('Hello ' * 100, level)
      expect(compressed.data).not_to have_key(:DecodeParms)
    end
  end

  it 'preserves decoder parameters and the original encoder options' do
    params = { level: Zlib::BEST_SPEED, Predictor: 1 }.freeze
    stream << 'Hello'
    stream.filters << { FlateDecode: params }

    expect(stream.data[:DecodeParms]).to eq [{ Predictor: 1 }]
    expect(stream.filters.normalized.first.last).to equal params
  end
end
