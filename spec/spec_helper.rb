require 'rspec'
require 'rspec/autorun' # For rcov to work properly

require 'mysql2'
require 'active_record'

begin
  require 'simplecov'
  if ENV["COVERAGE"]
    SimpleCov.start do
      add_filter "/spec/"
    end
  end
rescue LoadError
end
# requires after this line are included in coverage.

require File.dirname(__FILE__) + '/../lib/checkpointer'
#require 'lib/checkpointer'

# Require shared examples and other support files
Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.color_enabled = true
  config.formatter = 'documentation'
end
