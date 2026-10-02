# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Shared dev toolchain, consumed from the fork until it is released.
gem 'prawn-dev', git: 'https://github.com/jlsync/prawn-dev.git', branch: 'main'

# Evaluate Gemfile.local if it exists
if File.exist?("#{__FILE__}.local")
  instance_eval(File.read("#{__FILE__}.local"), "#{__FILE__}.local")
end
