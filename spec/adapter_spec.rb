require 'spec/spec_helper.rb'

module ::Checkpointer::Database
  describe Adapter do
    it_behaves_like 'a database adapter'
  end
end