require 'spec/spec_helper.rb'

module ::Checkpointer::Database
  describe Adapter do
    it_behaves_like 'a configured database adapter'
  end
end