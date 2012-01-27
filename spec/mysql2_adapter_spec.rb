require 'spec/spec_helper.rb'

module ::Checkpointer::Database
  describe Mysql2Adapter do
    it_behaves_like 'a configured database adapter'

    it 'should raise Checkpointer::Database::DuplicateTriggerError on duplicate trigger' do
      Mysql2::Client.any_instance.stub(:query).and_raise(Mysql2::Error.new("This version of MySQL doesn't yet support 'multiple triggers with the same action time and event for one table'"))

      c = described_class.new
      expect { c.execute('Add trigger') }.to raise_error(::Checkpointer::Database::DuplicateTriggerError)
    end
  end
end
