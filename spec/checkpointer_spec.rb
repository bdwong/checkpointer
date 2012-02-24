require File.dirname(__FILE__) + '/spec_helper.rb'

module Checkpointer
  class DummyAdapter < ::Checkpointer::Database::Adapter
    def self.configured?
      true
    end

    def initialize(options={})
      @options = options.merge({:database=>'database'})
    end

    def current_database
      @options[:database]
    end
  end

  describe Checkpointer do

    def stub_copy_tables_boilerplate
      @connection.stub(:execute).with('set autocommit = 0;')
      @connection.stub(:execute).with('set unique_checks = 0;')
      @connection.stub(:execute).with('set foreign_key_checks = 0;')
      
      @connection.stub(:execute).with('COMMIT;')
      @connection.stub(:execute).with('set foreign_key_checks = 1;')
      @connection.stub(:execute).with('set unique_checks = 1;')
      @connection.stub(:execute).with('set autocommit = 1;')
    end

    def stub_copy_table_needs_drop_and_create(fromdb, todb, table)
      DatabaseCopier.any_instance.stub(:show_create_table_without_increment).
        with(todb, table).
        and_return('FORCE DROP AND CREATE')
      DatabaseCopier.any_instance.stub(:show_create_table_without_increment).
        with(fromdb, table).
        and_return('BY RETURNING DIFFERENT VALUE')
      @connection.stub(:execute).with("DROP TABLE `#{todb}`.`#{table}`")
      @connection.stub(:execute).with("CREATE TABLE IF NOT EXISTS `#{todb}`.`#{table}` LIKE `#{fromdb}`.`#{table}`")
      Database::Tracker.any_instance.should_receive(:add_triggers_to_table).with(todb, table)
      @connection.stub(:execute).with("INSERT INTO `#{todb}`.`#{table}` SELECT * FROM `#{fromdb}`.`#{table}`")
    end

    def stub_copy_table_needs_creating(fromdb, todb, table)
      DatabaseCopier.any_instance.stub(:show_create_table_without_increment).
        with(todb, table).
        and_return(nil)
      DatabaseCopier.any_instance.stub(:show_create_table_without_increment).
        with(fromdb, table).
        and_return('THIS TABLE SHOULD BE CREATED')
      @connection.stub(:execute).with("CREATE TABLE IF NOT EXISTS `#{todb}`.`#{table}` LIKE `#{fromdb}`.`#{table}`")
      Database::Tracker.any_instance.should_receive(:add_triggers_to_table).with(todb, table)
      @connection.stub(:execute).with("INSERT INTO `#{todb}`.`#{table}` SELECT * FROM `#{fromdb}`.`#{table}`")
    end

    before(:each) do
      ::Checkpointer::Checkpointer.any_instance.stub(:autodetect_database_adapter).and_return(DummyAdapter)
    end

    # Test most of the functionality with database mocks.
    context "with dummy connection" do
      it "instantiates" do
        c = Checkpointer.new
        c.should be_kind_of(Checkpointer)
      end

      describe :extract_options do
        it "should delete :tables from @options" do
          c = Checkpointer.new({:database => 'db', :tables => :options})
          c.instance_variable_get(:@options).should == {:database => 'db'}
        end

        it "should add :tables to @cp_options" do
          c = Checkpointer.new({:database => 'db', :tables => :options})
          c.instance_variable_get(:@cp_options).should == {:tables => :options}
        end
      end      
    end

    context "instantiated with dummy connection" do
      before(:each) do
        @c = Checkpointer.new
        @connection = @c.sql_connection
        @connection.stub(:escape) {|value| value}
        @connection.stub(:identifier) {|value| "`#{value}`"}
        @connection.stub(:literal) {|value| "'#{value}'"}
        @connection.stub(:normalize_result) {|value| value}
        @connection.stub(:tables_from).with('database').and_return(['table_1', 'table_2'])

        # This should be unstubbed for individual cases if expecting queries:
        # @connection.unstub(:execute)
        @connection.stub(:execute) do |value|
          raise "Unexpected query string: \"#{value}\""
        end
      end

      describe :filtered_tables do
        it "should use @cp_options[:tables] if table_opts is nil" do
          @c.instance_variable_set(:@cp_options, { :tables => ['table_2']} )
          @c.filtered_tables(['table_1', 'table_2']).should == ['table_2']
        end

        it "should return all tables if @cp_options and table_opts are nil" do
          @c.filtered_tables(['table_1', 'table_2']).should == ['table_1', 'table_2']
        end

        it "should return all tables if table_opts is :all" do
          @c.filtered_tables(['table_1', 'table_2'], :all).should == ['table_1', 'table_2']
        end

        it "should return array minus nonexistent tables if table_opts is an array" do
          @c.filtered_tables(['table_1', 'table_2'], ['table_1', 'table_3']).should == ['table_1']
        end

        it "should return array minus nonexistent tables if table_opts has :only" do
          @c.filtered_tables(['table_1', 'table_2'], {:only => ['table_1', 'table_3']}).should == ['table_1']
        end

        it "should return tables minus exceptions if table_opts has :except" do
          @c.filtered_tables(['table_1', 'table_2'], {:except => ['table_1', 'table_3']}).should == ['table_2']
        end

        it "should combine :only and :except" do
          @c.filtered_tables(['table_1', 'table_2', 'table_3'], {:only => ['table_1', 'table_3'], :except => 'table_1'}).should == ['table_3']
        end

        it "should raise ArgumentError if passed an unknown argument type" do
          expect { @c.filtered_tables([], "invalid") }.to raise_error(ArgumentError)
        end
      end

      describe :sql_connection do
        it "has sql_connection DummyAdapter" do
          @c.sql_connection.should be_kind_of(DummyAdapter)
        end
      end

      describe :database do
        it "should return @db_name" do
          @c.database.should be @c.instance_variable_get(:@db_name)
        end
      end

      describe :track do
        it "should delegate to Database::Tracker and backup" do
          Database::Tracker.any_instance.should_receive(:track)
          dbcopier = double("DatabaseCopierInstance")
          dbcopier.stub(:copy_database).with('database', 'database_backup')
          DatabaseCopier.should_receive(:from_connection).and_return(dbcopier)

          @c.track
        end
      end

      describe :untrack do
        it "should delegate to Database::Tracker" do
          Database::Tracker.any_instance.should_receive(:untrack)
          @c.untrack
        end
      end

      describe :checkpoint do
        context "success" do
          before(:each) do
            @connection.unstub(:execute)
            @connection.should_receive(:execute).with('SELECT name FROM `database`.`updated_tables`').
              and_return(['table_1'])
          end

          it "should checkpoint the database" do
            DatabaseCopier.any_instance.should_receive(:create_database_for_copy).
              with('database', 'database_backup_1')
            DatabaseCopier.any_instance.should_receive(:copy_tables).
              with(['table_1', 'updated_tables'], 'database', 'database_backup_1')

            @c.checkpoint.should == 1
          end

          it "should checkpoint the next number" do
            DatabaseCopier.any_instance.should_receive(:create_database_for_copy).
              with('database', 'database_backup_3')
            DatabaseCopier.any_instance.should_receive(:copy_tables).
              with(['table_1', 'updated_tables'], 'database', 'database_backup_3')

            @c.instance_variable_set(:@checkpoint_number, 2)
            @c.checkpoint.should == 3
            @c.instance_variable_get(:@checkpoint_number).should == 3
          end

          it "should checkpoint by name if given a string" do
            DatabaseCopier.any_instance.should_receive(:create_database_for_copy).
              with('database', 'database_backup_custom')
            DatabaseCopier.any_instance.should_receive(:copy_tables).
              with(['table_1', 'updated_tables'], 'database', 'database_backup_custom')

            @c.checkpoint("custom").should == "custom"
          end
        end

        it "should raise ArgumentError if given a number" do
          expect{ @c.checkpoint(2) }.to raise_error(ArgumentError, "Manual checkpoints cannot be a number.")
        end
      end

      describe :restore do
        before(:each) do
          @connection.unstub(:execute)
          @connection.stub(:execute).with('SELECT name FROM `database`.`updated_tables`').
            and_return(['table_1', 'table_2'])
        end

        it "should restore the database to the last checkpoint" do
          @c.instance_variable_set(:@last_checkpoint, 2)
          @c.instance_variable_set(:@checkpoint_number, 2)
          @connection.should_receive(:tables_from).with('database_backup_2').
            and_return(['table_1', 'updated_tables'])

          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_2'], 'database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'updated_tables'], 'database_backup_2', 'database')
          @c.restore.should == 2
        end

        it "should restore to the base backup if there is no checkpoint" do
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'table_2'], 'database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with([], nil, 'database')
          @c.restore.should == 0
        end

        it "should restore to checkpoint by name if given a string" do
          @connection.should_receive(:tables_from).with('database_backup_special').
            and_return(['table_1', 'updated_tables'])

          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_2'], 'database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'updated_tables'], 'database_backup_special', 'database')
          @c.restore("special").should == "special"
        end

        it "should restore to checkpoint by number if given a number" do
          @connection.should_receive(:tables_from).with('database_backup_10').
            and_return(['table_1', 'updated_tables'])

          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_2'], 'database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'updated_tables'], 'database_backup_10', 'database')
          @c.restore(10).should == 10
        end

        # Verify that two callbacks get covered on copy_tables with a block.
        it "should call add_triggers_to_table if table needs to create or drop_and_create" do
          @c.instance_variable_set(:@last_checkpoint, 2)
          @c.instance_variable_set(:@checkpoint_number, 2)
          Database::Tracker.any_instance.should_receive(:tables_from).with('database_backup_2').
            and_return(['table_1'])

          stub_copy_tables_boilerplate
          stub_copy_table_needs_drop_and_create('database_backup', 'database', 'table_2')
          stub_copy_table_needs_creating('database_backup_2', 'database', 'table_1')

          @c.restore.should == 2
        end

        it "should restore with table options" do
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'table_2'], 'database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with([], nil, 'database')

          @c.should_receive(:filtered_tables).
            with([], {:except => 'table_3'}).
            and_return([])

          @c.should_receive(:filtered_tables).
            with(['table_1', 'table_2'], {:except => 'table_3'}).
            and_return(['table_1', 'table_2'])
          @c.restore(0, :except => 'table_3').should == 0
        end

        context "no backup database" do
          it "should raise an error if backup database does not exist" do
            DatabaseCopier.any_instance.should_receive(:copy_tables).
              with(['table_1', 'table_2'], 'database_backup', 'database').
              and_raise(::Checkpointer::Database::DatabaseNotFoundError.new)
            expect { @c.restore }.to raise_error(::Checkpointer::Database::DatabaseNotFoundError)
          end
        end

        context "checkpoint does not exist" do
          it "should raise an error if checkpoint does not exist" do
            Database::Tracker.any_instance.should_receive(:tables_from).with("database_backup_non_existent").
              and_raise(::Checkpointer::Database::DatabaseNotFoundError.new)
            expect { @c.restore("non_existent") }.to raise_error(::Checkpointer::Database::DatabaseNotFoundError)
          end
        end
      end

      describe :pop do
        before(:each) do
          @connection.unstub(:execute)
          @connection.stub(:execute).with('SELECT name FROM `database`.`updated_tables`').
            and_return(['table_1', 'table_2'])
        end

        it "should restore the highest checkpoint and drop it" do
          @c.instance_variable_set(:@last_checkpoint, 2)
          @c.instance_variable_set(:@checkpoint_number, 4)
          Database::Tracker.any_instance.should_receive(:tables_from).with('database_backup_4').
            and_return(['table_1', 'updated_tables'])
          @connection.should_receive(:execute).with("SHOW DATABASES LIKE 'database\\_backup\\_%'").
            and_return(['database_backup_1', 'database_backup_2', 'database_backup_3', 'database_backup_4'])
          @connection.should_receive(:execute).with('DROP DATABASE `database_backup_4`')

          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_2'], 'database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'updated_tables'], 'database_backup_4', 'database')
          @c.pop.should == 3
        end

      end

      describe :drop do
        it "should delegate numbers to drop_checkpoint_number" do
          @c.should_receive(:drop_checkpoint_number).with(3)
          @c.should_not_receive(:drop_checkpoint_name)

          @c.drop(3)
        end

        it "should delegate strings to drop_checkpoint_by_name" do
          @c.should_receive(:drop_checkpoint_name).with("name")
          @c.should_not_receive(:drop_checkpoint_number)

          @c.drop("name")
        end

        it "should default to the highest checkpoint number" do
          @c.instance_variable_set(:@last_checkpoint, 2)
          @c.instance_variable_set(:@checkpoint_number, 4)
          @c.should_receive(:drop_checkpoint_number).with(4)

          @c.drop
        end
      end

      describe :drop_checkpoint_number do
        it "should drop checkpoints on or above a number" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("SHOW DATABASES LIKE 'database\\_backup\\_%'").
            and_return(['database_backup_1', 'database_backup_2', 'database_backup_3', 'database_backup_4'])
          @connection.should_receive(:execute).with('DROP DATABASE `database_backup_3`')
          @connection.should_receive(:execute).with('DROP DATABASE `database_backup_4`')

          @c.drop(3).should == 2
        end
      end

      describe :drop_checkpoint_name do
        it "should drop checkpoint by name" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("SHOW DATABASES LIKE 'database\\_backup\\_%'").
            and_return(['database_backup_1', 'database_backup_start', 'database_backup_2'])
          @connection.should_receive(:execute).with('DROP DATABASE `database_backup_start`')
          @c.drop("start")
        end

        it "should change the last checkpoint to a number if the last checkpoint was dropped" do
          @c.instance_variable_set(:@checkpoint_number, 2)
          @c.instance_variable_set(:@last_checkpoint, "this_one")

          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("SHOW DATABASES LIKE 'database\\_backup\\_%'").
            and_return(['database_backup_1', 'database_backup_this_one', 'database_backup_2'])
          @connection.should_receive(:execute).with('DROP DATABASE `database_backup_this_one`')
          @c.drop("this_one").should == 2

          @c.instance_variable_get(:@last_checkpoint).should == 2
        end

        it "should return nil if the checkpoint was not found" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("SHOW DATABASES LIKE 'database\\_backup\\_%'").
            and_return(['database_backup_1', 'database_backup_2'])
          @connection.should_not_receive(:execute).with('DROP DATABASE `database_backup_non_existent`')
          @c.drop("non_existent").should be_nil
        end

      end

      describe :checkpoints do
        it "should list checkpoints for the database" do
          @connection.should_receive(:execute).with("SHOW DATABASES LIKE 'database\\_backup\\_%'").
            and_return(['database_backup_1', 'database_backup_special', 'database_backup_2'])

          @c.checkpoints.should == ['1', 'special', '2']
        end
      end

      describe :backup do
        it "should delegate to DatabaseCopier" do
          DatabaseCopier.any_instance.should_receive(:copy_database).
            with('database', 'database_backup')
          @c.backup
        end
      end

      describe :restore_all do
        it "should restore database using DatabaseCopier" do
          Database::Tracker.any_instance.should_receive(:tables_from).with('database_backup').and_return(['table_1', 'table_2'])
          DatabaseCopier.any_instance.should_receive(:drop_tables_not_in_source).
            with('database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'table_2'], 'database_backup', 'database')
          Database::Tracker.any_instance.should_receive(:create_tracking_table)

          @c.restore_all
        end
        
        it "should call add_triggers_to_table if table needs to create or drop_and_create" do
          Database::Tracker.any_instance.should_receive(:tables_from).with('database_backup').
            and_return(['table_1', 'table_2'])

          stub_copy_tables_boilerplate
          DatabaseCopier.any_instance.stub(:drop_tables_not_in_source)
          stub_copy_table_needs_drop_and_create('database_backup', 'database', 'table_1')
          stub_copy_table_needs_creating('database_backup', 'database', 'table_2')
          Database::Tracker.any_instance.should_receive(:create_tracking_table)

          @c.restore_all
        end
      end

      describe :is_number? do
        it "should return true for numbers and strings that are numbers" do
          @c.send(:is_number?, "123").should be_true
          @c.send(:is_number?, "0").should be_true
          @c.send(:is_number?, 10).should be_true
        end

        it "should return false for non-numbers" do
          @c.send(:is_number?, "abc").should be_false
          @c.send(:is_number?, [2]).should be_false
          @c.send(:is_number?, {1 => 1}).should be_false
          @c.send(:is_number?, :symbol).should be_false
        end

        it "should return false for strings that contain both alpha and numeric digits" do
          @c.send(:is_number?, "123abc").should be_false
          @c.send(:is_number?, "abc123").should be_false
        end
      end
    end
  end
end