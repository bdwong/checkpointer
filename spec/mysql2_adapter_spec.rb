require 'spec/spec_helper.rb'

module ::Checkpointer::Database
  describe Mysql2Adapter do
    it_behaves_like 'a configured database adapter'

    it 'should raise Checkpointer::Database::DuplicateTriggerError on duplicate trigger' do
      Mysql2::Client.any_instance.stub(:query).and_raise(Mysql2::Error.new("This version of MySQL doesn't yet support 'multiple triggers with the same action time and event for one table'"))

      c = described_class.new
      expect { c.execute('Add trigger') }.to raise_error(::Checkpointer::Database::DuplicateTriggerError)
    end

    context "instantiated" do
      before(:each) do
        @c = described_class.new
      end

      describe :current_database do
        it 'should return the current database' do
          Mysql2::Client.any_instance.should_receive(:query).with('SELECT DATABASE();').
            and_return([{"DATABASE()" => "current_database"}])

          @c.current_database.should == "current_database"
        end
      end

      describe :connection do
        it 'should return a Mysql2::Client' do
          @c.connection.kind_of?(Mysql2::Client).should be_true
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
          Mysql2::Client.any_instance.should_receive(:query).and_raise(Mysql2::Error.new("A 'multiple triggers' error"))
          expect { @c.execute("SELECT 1") }.to raise_error(::Checkpointer::Database::DuplicateTriggerError, "Unhandled duplicate trigger")
        end

        it 'should re-raise other errors' do
          Mysql2::Client.any_instance.should_receive(:query).and_raise(Mysql2::Error.new("Some non-trigger error"))
          expect { @c.execute("SELECT 1") }.to raise_error(Mysql2::Error, "Some non-trigger error")
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
          @c.identifier("blah\\identifier").should == '`blah\\\\identifier`'
        end

        it 'should escape and quote backtick' do
          @c.identifier("blah\`identifier").should == '`blah\\`identifier`'
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
          Mysql2::Client.any_instance.should_receive(:query).with('SHOW TABLES FROM `mydb`').
            and_return([{"Tables_in_mydb"=>"first_table"}, {"Tables_in_mydb"=>"second_table"}])
 
          @c.tables_from("mydb").should == ["first_table", "second_table"]
        end
      end

      describe :show_create_table do
        it 'should return the create table string from the driver' do
          Mysql2::Client.any_instance.should_receive(:query).with('SHOW CREATE TABLE `mydb`.`mytable`').
            and_return(
            [{"Create Table"=>'CREATE TABLE `mytable` etc.',
              "Table"=>"mytable"}]
            )
 
          @c.show_create_table("mydb", "mytable").should == 'CREATE TABLE `mytable` etc.'
        end

        it 'should return nil if table does not exist' do
          Mysql2::Client.any_instance.should_receive(:query).with('SHOW CREATE TABLE `mydb`.`non-existent`').
            and_raise(Mysql2::Error.new("Table \`non-existent\` doesn't exist"))

          @c.show_create_table("mydb", "non-existent").should be_nil
        end

        it 'should re-raise on other error' do
          Mysql2::Client.any_instance.should_receive(:query).with('SHOW CREATE TABLE `mydb`.`mytable`').
            and_raise(Mysql2::Error.new("Other error"))

          expect { @c.show_create_table("mydb", "mytable") }.to raise_error(Mysql2::Error, "Other error")
        end
      end

      describe :normalize_result do
      end
      # # Normalize result of single-column queries into an array.
      # def normalize_result(result)
      #   result.map{|h| h.values}.flatten
      # end    
    end
  end
end
