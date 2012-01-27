#require 'simplecov'

# SimpleCov.start do
#   add_filter "spec/"
# end

require 'rspec'
require 'mysql2'
require 'active_record'
require 'lib/checkpointer'

# Require shared examples and other support files
Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.color_enabled = true
  config.formatter = 'documentation'
end
