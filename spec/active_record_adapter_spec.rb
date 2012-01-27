require 'spec/spec_helper.rb'

# Utility methods to hide ActiveRecord for testing.
def hide_active_record
  Object.const_set(:ActiveRecordHidden, ::ActiveRecord)
  Object.send(:remove_const, :ActiveRecord)
end

def unhide_active_record
  Object.const_set(:ActiveRecord, ::ActiveRecordHidden)
  Object.send(:remove_const, :ActiveRecordHidden)
end

module ::Checkpointer::Database
  
  describe ActiveRecordAdapter do
    it_behaves_like 'a database adapter'

    describe 'self.configured?' do
      it 'should return true if both ActiveRecord and its connection are configured.' do
        ActiveRecord::Base.stub(:connection).and_return(true)

        described_class.should be_configured
      end

      context "ActiveRecord not defined" do
        before(:all) { hide_active_record }
        after(:all) { unhide_active_record }

        it 'should return false if ActiveRecord is not loaded' do
          described_class.stub(:active_record_base).and_raise(NameError.new('uninitialized constant ActiveRecord'))

          described_class.should_not be_configured
        end
      end

      it 'should return false if ActiveRecord is loaded but the connection is not configured' do
        ActiveRecord::Base.stub(:connection).and_raise(ActiveRecord::ConnectionNotEstablished.new('Connection not established'))

        described_class.should_not be_configured
      end
    end

    describe 'self.has_active_record?' do
      it 'should return true if ActiveRecord is found' do
        described_class.should have_active_record
      end

      context "ActiveRecord not defined" do
        before(:all) { hide_active_record }
        after(:all) { unhide_active_record }

        it 'should return false if ActiveRecord is not found' do
          described_class.should_not have_active_record
        end
      end
    end

    describe 'self.has_active_record_connection?' do
      it 'should return true if ActiveRecord has a connection' do
        ActiveRecord::Base.stub(:connection).and_return(true)

        described_class.should have_active_record_connection
      end

      it 'should return false if ActiveRecord has no connection' do
        ActiveRecord::Base.stub(:connection).and_raise(ActiveRecord::ConnectionNotEstablished.new('Connection not established'))

        described_class.should_not have_active_record_connection
      end
    end

    context "instantiated with heavily stubbed ActiveRecord::Base" do
      def stub_active_record
        @connection = double('ActiveRecord::ConnectionAdapters::Mysql2Adapter')
        #@connection.stub
        @active_record_base = double('ActiveRecord::Base')
        @active_record_base.stub(:connection).and_return(@connection)
        described_class.stub(:active_record_base => @active_record_base)
      end

      it 'should raise Checkpointer::Database::DuplicateTriggerError on duplicate trigger' do
        stub_active_record
        c = described_class.new
        @connection.stub(:execute).and_raise(ActiveRecord::StatementInvalid.new("This version of MySQL doesn't yet support 'multiple triggers with the same action time and event for one table'"))
        expect { c.execute('Add trigger') }.to raise_error(::Checkpointer::Database::DuplicateTriggerError)
      end
    end


  end
end