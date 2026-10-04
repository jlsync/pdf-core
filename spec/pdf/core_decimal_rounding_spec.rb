# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PDF::Core do
  example_group 'Decimal rounding' do
    it 'rounds floating point numbers to four decimal places' do
      expect(described_class.real(1.23456789)).to eq '1.23457'
    end

    it 'is able to create a PDF parameter list of rounded decimals' do
      expect(described_class.real_params([1, 2.345678, Math::PI]))
        .to eq '1.0 2.34568 3.14159'
    end

    it 'keeps a single fraction digit for integral values' do
      expect(described_class.real(0)).to eq '0.0'
      expect(described_class.real(-12)).to eq '-12.0'
      expect(described_class.real(2**70)).to eq "#{2**70}.0"
      expect(described_class.real(0.0)).to eq '0.0'
      expect(described_class.real(-0.0)).to eq '-0.0'
      expect(described_class.real(150.0)).to eq '150.0'
      expect(described_class.real(1e15)).to eq '1000000000000000.0'
      expect(described_class.real(1e20)).to eq '100000000000000000000.0'
    end

    it 'strips trailing zeroes from the rounded fraction' do
      expect(described_class.real(1.5)).to eq '1.5'
      expect(described_class.real(100.05)).to eq '100.05'
      expect(described_class.real(0.000004)).to eq '0.0'
      expect(described_class.real(-0.000004)).to eq '-0.0'
      expect(described_class.real(0.999996)).to eq '1.0'
      expect(described_class.real(Rational(1, 4))).to eq '0.25'
    end

    it 'serializes non-finite numbers as before' do
      expect(described_class.real(Float::INFINITY)).to eq 'Inf'
      expect(described_class.real(Float::NAN)).to eq 'NaN'
      expect(described_class.real(Float::NAN)).to eq 'NaN'
    end

    # Values that need format('%.5f') are cached, so what callers receive must
    # not be the cached object: pdf_object trims a trailing '.0' in place.
    it 'returns an isolated copy for repeated values' do
      expect(described_class.real(0.999996)).to eq '1.0'

      described_class.real(0.999996).chomp!('.0')

      expect(described_class.real(0.999996)).to eq '1.0'
    end

    it 'returns a string the caller may modify' do
      described_class.real(1.23456789) << 'junk'

      expect(described_class.real(1.23456789)).to eq '1.23457'
    end

    # 0.0 and -0.0 hash equal, so the cache has to sit behind the integral
    # fast path that tells them apart.
    it 'keeps negative zero distinct from zero' do
      expect(described_class.real(0.0)).to eq '0.0'
      expect(described_class.real(-0.0)).to eq '-0.0'
      expect(described_class.real(0.0)).to eq '0.0'
      expect(described_class.real(-0.0)).to eq '-0.0'
    end
  end
end
