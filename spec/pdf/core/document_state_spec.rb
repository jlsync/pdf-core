# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PDF::Core::DocumentState do
  subject(:state) { described_class.new({}) }

  describe 'initialization' do
    it { expect(state.compress).to be false }
    it { expect(state.encrypt).to be false }
    it { expect(state.skip_encoding).to be false }
    it { expect(state.trailer).to eq({}) }
  end

  describe 'normalize_metadata' do
    it { expect(state.store.info.data[:Creator]).to eq('Prawn') }
    it { expect(state.store.info.data[:Producer]).to eq('Prawn') }
  end

  describe 'given a trailer ID with two values' do
    subject(:state) do
      described_class.new(
        trailer: { ID: %w[myDoc versionA] },
      )
    end

    it 'contains the ID entry with two values in trailer' do
      expect(state.trailer[:ID].count).to eq(2)
    end
  end

  describe 'populate_pages_from_store' do
    subject(:state) { described_class.new({}) }

    let(:renderer) { PDF::Core::Renderer.new(state) }

    before do
      renderer
      store = state.store
      # Ids well clear of the low ids Page#initialize allocates for its content
      # and dictionary objects, which would otherwise overwrite these entries.
      3.times { |i| store.push(i + 100, { Type: :Page }) }
      store.pages.data[:Kids].concat((100..102).map { |id| store[id] })
      store.pages.data[:Count] = 3
    end

    it 'loads one page per page object' do
      state.populate_pages_from_store(renderer)
      expect(state.pages.length).to eq 3
      expect(state.pages).to all(be_a(PDF::Core::Page))
    end

    it 'loads one page per Count entry, even past the end of the kid list' do
      state.store.pages.data[:Count] = 5
      state.populate_pages_from_store(renderer)
      expect(state.pages.length).to eq 5
    end

    it 'does nothing when pages are already loaded' do
      state.populate_pages_from_store(renderer)
      expect(state.populate_pages_from_store(renderer)).to eq 0
    end
  end
end
