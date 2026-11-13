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

    it 'preserves signed zeroes and cached values in parameter lists' do
      expect(described_class.real_params([0, 0.0, -0.0, 1.0 / 7.0, 1.0 / 7.0]))
        .to eq '0.0 0.0 -0.0 0.14286 0.14286'
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

    # The same hazard for non-Float numerics, where no fast path tells the two
    # apart: only Float is cached for this reason.
    it 'keeps signed zeroes apart for non-Float numerics' do
      expect(described_class.real(Complex(0.0, 0))).to eq '0.0'
      expect(described_class.real(Complex(-0.0, 0))).to eq '-0.0'
      expect(described_class.real(Complex(0.0, 0))).to eq '0.0'
      expect(described_class.real(Complex(-0.0, 0))).to eq '-0.0'
    end

    it 'still caches repeated Float values' do
      described_class.real(1.23456789).chomp!('.0')

      expect(described_class.real(1.23456789)).to eq '1.23457'
    end

    it 'keeps real, append_real, pdf_object, and append_pdf_float aligned' do
      expected = [
        [0, '0.0', '0'],
        [-12, '-12.0', '-12'],
        [2**70, '1180591620717411303424.0', '1180591620717411303424'],
        [0.0, '0.0', '0'],
        [-0.0, '-0.0', '-0'],
        [150.0, '150.0', '150'],
        [1e15, '1000000000000000.0', '1000000000000000'],
        [1e20, '100000000000000000000.0', '100000000000000000000'],
        [1.5, '1.5', '1.5'],
        [100.05, '100.05', '100.05'],
        [0.000004, '0.0', '0'],
        [-0.000004, '-0.0', '-0'],
        [0.999996, '1.0', '1'],
        [1.0 / 7.0, '0.14286', '0.14286'],
        [Rational(1, 4), '0.25', '0.25'],
        [Complex(0.0, 0), '0.0', '0'],
        [Complex(-0.0, 0), '-0.0', '-0'],
        [Float::INFINITY, 'Inf', 'Inf'],
        [Float::NAN, 'NaN', 'NaN'],
      ]

      expected.each do |(value, expected_real, expected_pdf)|
        expect(described_class.real(value)).to eq expected_real
        expect(described_class.append_real(+'p ', value)).to eq "p #{expected_real}"
        expect(described_class.pdf_object(value, true)).to eq expected_pdf
        expect(described_class.append_pdf_object(+'p ', value, true))
          .to eq "p #{expected_pdf}"
      end
    end
  end
end
