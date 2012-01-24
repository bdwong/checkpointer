#require 'simplecov'

# SimpleCov.start do
#   add_filter "spec/"
# end

require 'rspec'
require 'checkpointer'

RSpec.configure do |config|
  config.color_enabled = true
  config.formatter = 'documentation'
end
