# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PDF::Core::ObjectStore do
  subject(:store) { described_class.new }

  it 'creates required roots by default, including info passed to new' do
    store = described_class.new(info: { Test: 3 })
    expect(store.size).to eq 3 # 3 default roots
    expect(store.info.data[:Test]).to eq 3
    expect(store.pages.data[:Count]).to eq 0
    expect(store.root.data[:Pages]).to eq store.pages
  end

  it 'adds to its objects when ref() is called' do
    count = store.size
    store.ref('blah')
    expect(store.size).to eq count + 1
  end

  it 'accepts push with a Prawn::Reference' do
    r = PDF::Core::Reference.new(123, 'blah')
    store.push(r)
    expect(store[r.identifier]).to eq r
  end

  it 'accepts arbitrary data and use it to create a Prawn::Reference' do
    store.push(123, 'blahblah')
    expect(store[123].data).to eq 'blahblah'
  end

  it 'is Enumerable, yielding in order of submission' do
    # higher IDs to bypass the default roots
    [10, 11, 12].each do |id|
      store.push(id, "some data #{id}")
    end
    expect(store.map(&:identifier)[-3..]).to eq [10, 11, 12]
  end

  it 'accepts option to disabling PDF scaling in PDF clients' do
    store = described_class.new(print_scaling: :none)
    expect(store.root.data[:ViewerPreferences]).to eq PrintScaling: :None
  end

  describe 'page object ids' do
    before do
      # Higher IDs to bypass the default roots.
      5.times { |i| store.push(i + 10, { Type: :Page }) }
      store.pages.data[:Kids].concat((10..14).map { |id| store[id] })
      store.pages.data[:Count] = 5
    end

    it 'lists every page identifier in page order' do
      expect(store.page_object_ids).to eq [10, 11, 12, 13, 14]
    end

    it 'indexes pages from one' do
      expect(store.object_id_for_page(1)).to eq 10
      expect(store.object_id_for_page(5)).to eq 14
    end

    it 'indexes negative page numbers from the end' do
      expect(store.object_id_for_page(-1)).to eq 14
      expect(store.object_id_for_page(-5)).to eq 10
    end

    it 'returns nil past the last page' do
      expect(store.object_id_for_page(6)).to be_nil
    end
  end
end
