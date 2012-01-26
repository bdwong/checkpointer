require 'spec/spec_helper.rb'

module ::Checkpointer::Database
  describe Mysql2Adapter do
    it_behaves_like 'a database adapter'
  end
end
