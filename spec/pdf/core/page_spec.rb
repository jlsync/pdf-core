# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PDF::Core::Page do
  let(:doc) do
    document_class =
      Class.new do
        def initialize
          @store = PDF::Core::ObjectStore.new
          @state = PDF::Core::DocumentState.new({})
          @renderer = PDF::Core::Renderer.new(@state)
        end
        attr_reader :state

        def ref(*args)
          @renderer.ref(*args)
        end

        def save_graphics_state; end

        def freeze_stamp_graphics; end
      end
    document_class.new
  end

  it 'embeds MediaBox' do
    page = described_class.new(doc, size: 'A4')

    expect(page.dictionary.data[:MediaBox]).to eq [0, 0, 595.28, 841.89]
  end

  it 'embeds CropBox' do
    page = described_class.new(
      doc,
      size: 'A4',
      crops: { left: 10, bottom: 20, right: 30, top: 40 },
    )

    expect(page.dictionary.data[:CropBox]).to eq [10, 20, 565.28, 801.89]
  end

  it 'embeds BleedBox' do
    page = described_class.new(
      doc,
      size: 'A4',
      bleeds: { left: 10, bottom: 20, right: 30, top: 40 },
    )

    expect(page.dictionary.data[:BleedBox]).to eq [10, 20, 565.28, 801.89]
  end

  it 'embeds TrimBox' do
    page = described_class.new(
      doc,
      size: 'A4',
      trims: { left: 10, bottom: 20, right: 30, top: 40 },
    )

    expect(page.dictionary.data[:TrimBox]).to eq [10, 20, 565.28, 801.89]
  end

  it 'embeds ArtBox' do
    page = described_class.new(
      doc,
      size: 'A4',
      art_indents: { left: 10, bottom: 20, right: 30, top: 40 },
    )

    expect(page.dictionary.data[:ArtBox]).to eq [10, 20, 565.28, 801.89]
  end

  describe 'stamp_stream' do
    it 'is writable' do
      page = described_class.new(doc, size: 'A4')

      ref = PDF::Core::Reference.new(1, {})

      expect {
        page.stamp_stream(ref) do
          page.content << 'test'
        end
      }.to_not raise_error
      expect(ref.stream.filtered_stream).to eq 'test'
    end

    it 'invalidates cached references when object store is replaced' do
      page = described_class.new(doc, size: 'A4')
      original_content = page.content

      new_store = PDF::Core::ObjectStore.new
      new_ref = new_store.push(page.content.identifier, { Replaced: true })
      doc.state.store = new_store

      expect(page.content).to eq new_ref
      expect(page.content.data[:Replaced]).to be true
      expect(page.content).to_not eq original_content
    end
  end
end
