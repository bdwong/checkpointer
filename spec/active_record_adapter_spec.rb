require 'spec/spec_helper.rb'
require 'active_record/connection_adapters/mysql2_adapter'
require 'pry'

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
    it_behaves_like 'an unconfigured database adapter'

    describe 'self.configured?' do
      context "ActiveRecord defined and connection configured" do
        before (:each) do
          ActiveRecord::Base.stub(:connection).and_return(true)
        end

        it_behaves_like 'a configured database adapter'

        it 'should return true if both ActiveRecord and its connection are configured.' do
          described_class.should be_configured
        end
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

    context "instantiated with stubbed ActiveRecord::Base" do
      before(:each) do
        @connection = ActiveRecord::Base.mysql2_connection({})
        ActiveRecord::Base.stub(:connection).and_return(@connection)

        @c = described_class.new
      end

      it 'should raise Checkpointer::Database::DuplicateTriggerError on duplicate trigger' do
        @connection.stub(:execute).and_raise(ActiveRecord::StatementInvalid.new("This version of MySQL doesn't yet support 'multiple triggers with the same action time and event for one table'"))
        expect { @c.execute('Add trigger') }.to raise_error(::Checkpointer::Database::DuplicateTriggerError)
      end

      describe :current_database do
        it 'should return the current database' do
          @connection.should_receive(:execute).with('SELECT DATABASE();').
            and_return([["current_database"]])

          @c.current_database.should == "current_database"
        end
      end

      describe :connection do
        it 'should return a ActiveRecord::ConnectionAdapters::Mysql2Adapter' do
          @c.connection.kind_of?(ActiveRecord::ConnectionAdapters::Mysql2Adapter).should be_true
        end
      end

      describe :close_connection do
        it 'should close the connection' do
          @c.close_connection.should be_nil
        end
      end

      describe :execute do
        it 'should execute the query' do
          result = @c.execute("SELECT 1")
          result.kind_of?(Mysql2::Result).should be_true
        end

        it 'should raise DuplicateTriggerError on multiple triggers' do
          @connection.should_receive(:execute).and_raise(ActiveRecord::StatementInvalid.new("A 'multiple triggers' error"))
          expect { @c.execute("SELECT 1") }.to raise_error(::Checkpointer::Database::DuplicateTriggerError, "Unhandled duplicate trigger")
        end

        it 'should re-raise other errors' do
          @connection.should_receive(:execute).and_raise(ActiveRecord::StatementInvalid.new("Some non-trigger error"))
          expect { @c.execute("SELECT 1") }.to raise_error(ActiveRecord::StatementInvalid, "Some non-trigger error")
        end

      end

      describe :escape do
        it 'should escape single quotes' do
          @c.escape("'test'").should == "\\'test\\'"
        end

        it 'should escape backslash' do
          @c.escape("blah\\blah").should == "blah\\\\blah"
        end

        it 'should not escape backquote' do
          @c.escape("blah\`blah").should == "blah\`blah"
        end
      end

      describe :identifier do
        it 'should not escape single quotes' do
          @c.identifier("'test'").should == '`\'test\'`'
        end
        
        it 'should escape and quote backslash' do
          @c.identifier("blah\\identifier").should == '`blah\\identifier`'
        end

        it 'should escape and quote backtick' do
          @c.identifier("blah\`identifier").should == '`blah``identifier`'
        end
      end

      describe :literal do
        it 'should escape single quotes' do
          @c.literal("'test'").should == "'\\'test\\''"
        end

        it 'should escape double quotes' do
          @c.literal('"test"').should == "'\\\"test\\\"'"
        end

        it 'should escape backslash' do
          @c.literal("blah\\identifier").should == "'blah\\\\identifier'"
        end

        it 'should not escape backquote' do
          @c.literal("blah\`blah").should == "'blah\`blah'"
        end
      end

      describe :tables_from do
        it 'should return the list tables in a database' do
          @result = [["first_table"], ["second_table"]]
          @result.stub(:fields).and_return(["Tables_in_mydb"])
          Mysql2::Client.any_instance.should_receive(:query).with('SHOW TABLES FROM `mydb`').
            and_return(@result)
 
          @c.tables_from("mydb").should == ["first_table", "second_table"]
        end
      end

      describe :show_create_table do
        it 'should return the create table string from the driver' do
          @connection.should_receive(:execute).with('SHOW CREATE TABLE `mydb`.`mytable`').
            and_return(
            [['mytable', 'CREATE TABLE `mytable` etc.']]
            )
 
          @c.show_create_table("mydb", "mytable").should == 'CREATE TABLE `mytable` etc.'
        end

        it 'should return nil if table does not exist' do
          Mysql2::Client.any_instance.should_receive(:query).with('SHOW CREATE TABLE `mydb`.`non-existent`').
            and_raise(Mysql2::Error.new("Table \`non-existent\` doesn't exist"))

          @c.show_create_table("mydb", "non-existent").should be_nil
        end

        it 'should re-raise on other error' do
          @connection.should_receive(:execute).with('SHOW CREATE TABLE `mydb`.`mytable`').
            and_raise(ActiveRecord::StatementInvalid.new("Other error"))

          expect { @c.show_create_table("mydb", "mytable") }.to raise_error(ActiveRecord::StatementInvalid, "Other error")
        end
      end

      describe :normalize_result do
        it 'should normalize the result into a single array' do
          @result = [["Column 1 Value 1"], ["Column 1 Value 2"]]
          @result.stub(:fields).and_return(["column_1"])
          @c.normalize_result(@result).should ==
            ["Column 1 Value 1", "Column 1 Value 2"]
        end
      end

      describe :column_values do
        before(:each) do
          @result = [
            ["Column 1 Value 1", "Column 2 Value 1"],
            ["Column 1 Value 2", "Column 2 Value 2"]
          ]
          @result.stub(:fields).and_return(["column_1", "column_2"])
        end

        it 'should get the first result column into a single array' do
          @c.column_values(@result, 0).should ==
            ["Column 1 Value 1", "Column 1 Value 2"]
        end

        it 'should return the first result column by default' do
          @c.column_values(@result).should ==
            ["Column 1 Value 1", "Column 1 Value 2"]
        end

        it 'should get the second result column into a single array' do
          @c.column_values(@result, 1).should ==
            ["Column 2 Value 1", "Column 2 Value 2"]
        end

        it 'should get the first result column by name' do
          @c.column_values(@result, "column_1").should ==
            ["Column 1 Value 1", "Column 1 Value 2"]
        end

        it 'should get the second result column by name' do
          @c.column_values(@result, "column_2").should ==
            ["Column 2 Value 1", "Column 2 Value 2"]
        end

        it 'should return nil if named column is not found' do
          @c.column_values(@result, "column_x").should be_nil
        end

        it 'should return nil if column does not exist' do
          @c.column_values(@result, 99).should be_nil
        end
      end
    end
  end
end