# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
end

require_relative '../lib/pdf/core'

require 'rspec'
require 'securerandom'
require 'pdf/reader'
require 'pdf/inspector'

# rubocop: disable Style/SymbolProc
RSpec.configure do |config|
  config.disable_monkey_patching!
end
# rubocop: enable Style/SymbolProc

RSpec::Matchers.define(:have_parseable_xobjects) do
  match do |actual|
    expect { PDF::Inspector::XObject.analyze(actual.render) }.to_not raise_error
    true
  end
  failure_message_for_should do |actual|
    "expected that #{actual}'s XObjects could be successfully parsed"
  end
end

# pdf-inspector 1.3.0 (last released 2017) calls
# PDF::Reader::Parser.new(buffer, nil) with a second positional argument.
# pdf-reader 2.16.0 turned that argument into a keyword, so the positional
# form raises ArgumentError. Passing no argument is equivalent, because
# "objects:" already defaults to nil.
module PDF
  # Patches PDF::Inspector's parser call to match pdf-reader's keyword API.
  class Inspector
    # Parses a single PDF object out of a string.
    def self.parse(obj)
      PDF::Reader::Parser.new(PDF::Reader::Buffer.new(StringIO.new(obj))).parse_token
    end
  end
end
