require File.dirname(__FILE__) + '/spec_helper.rb'

# Fake out ActiveRecord for testing.
module ActiveRecord
  if not const_defined?(:ConnectionNotEstablished)
    class ConnectionNotEstablished < Exception; end
  end
end

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
      @c.should_receive(:add_triggers_to_table).with(todb, table)
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
      @c.should_receive(:add_triggers_to_table).with(todb, table)
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

      describe :tracking_table do
        it "should be 'updated_tables'" do
          @c.tracking_table.should == "updated_tables"
        end
      end

      describe :track do
        it "should start tracking database changes" do
          @connection.unstub(:execute)

          @connection.should_receive(:execute).with("DROP TABLE IF EXISTS `database`.`updated_tables`;")
          @connection.should_receive(:execute).with("CREATE TABLE IF NOT EXISTS `database`.`updated_tables`(name char(64), PRIMARY KEY (name));")

          @connection.should_receive(:execute).with(/^\s*CREATE TRIGGER `database`.`table_1_/).exactly(3).times
          @connection.should_receive(:execute).with(/^\s*CREATE TRIGGER `database`.`table_2_/).exactly(3).times

          dbcopier = double("DatabaseCopierInstance")
          dbcopier.stub(:copy_database).with('database', 'database_backup')
          DatabaseCopier.should_receive(:from_connection).and_return(dbcopier)

          # Catch unexpected queries, must go last.
          @connection.stub(:execute) do |value|
            raise "Unexpected query string: \"#{value}\""
          end

          @c.track
        end
      end

      describe :untrack do
        it "should stop tracking the database" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with(/^DROP TRIGGER.*table_1/).exactly(3).times
          @connection.should_receive(:execute).with(/^DROP TRIGGER.*table_2/).exactly(3).times
          @connection.should_receive(:execute).with("DROP TABLE IF EXISTS `database`.`updated_tables`;")

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
          @connection.should_receive(:tables_from).with('database_backup_2').
            and_return(['table_1'])

          stub_copy_tables_boilerplate
          stub_copy_table_needs_drop_and_create('database_backup', 'database', 'table_2')
          stub_copy_table_needs_creating('database_backup_2', 'database', 'table_1')

          @c.restore.should == 2
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
            @c.should_receive(:tables_from).with("database_backup_non_existent").
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
          @connection.should_receive(:tables_from).with('database_backup_4').
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
          @connection.unstub(:execute)
          @connection.stub(:tables_from).with('database_backup').and_return(['table_1', 'table_2'])
          DatabaseCopier.any_instance.should_receive(:drop_tables_not_in_source).
            with('database_backup', 'database')
          DatabaseCopier.any_instance.should_receive(:copy_tables).
            with(['table_1', 'table_2'], 'database_backup', 'database')
          @connection.should_receive(:execute).
            with("CREATE TABLE IF NOT EXISTS `database`.`updated_tables`(name char(64), PRIMARY KEY (name));")
          @c.restore_all
        end
        
        it "should call add_triggers_to_table if table needs to create or drop_and_create" do
          @connection.should_receive(:tables_from).with('database_backup').
            and_return(['table_1', 'table_2'])

          stub_copy_tables_boilerplate
          DatabaseCopier.any_instance.stub(:drop_tables_not_in_source)
          stub_copy_table_needs_drop_and_create('database_backup', 'database', 'table_1')
          stub_copy_table_needs_creating('database_backup', 'database', 'table_2')

          @c.should_receive(:create_tracking_table)

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

      describe :tables_from do
        it "should return all tables in the database" do
          @c.send(:tables_from, 'database').should == ['table_1', 'table_2']
        end

        it "should return the tracking table among all tables in the database" do
          @connection.stub(:tables_from).with('database').and_return(['table_1', 'table_2', 'updated_tables'])
          @c.send(:tables_from, 'database').should == ['table_1', 'table_2', 'updated_tables']
        end

        it "should always put the tracking table last" do
          @connection.stub(:tables_from).with('database').and_return(['updated_tables', 'table_1', 'table_2'])
          @c.send(:tables_from, 'database').should == ['table_1', 'table_2', 'updated_tables']
        end
      end

      describe :changed_tables_from do
        it "should list all records in the tracking table (tracking table not included)" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with('SELECT name FROM `database`.`updated_tables`').
            and_return(['table_1'])
          @c.send(:changed_tables_from, 'database').should == ['table_1']
        end
      end

      describe :create_tracking_table do
        it "should create the tracking table" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("CREATE TABLE IF NOT EXISTS `database`.`updated_tables`(name char(64), PRIMARY KEY (name));")
          @c.send(:create_tracking_table)
        end
      end

      describe :drop_tracking_table do
        it "should drop the tracking table" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("DROP TABLE IF EXISTS `database`.`updated_tables`;")
          @c.send(:drop_tracking_table)
        end
      end

      describe :add_triggers do
        it "should add triggers to tables in the database" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_1_insert` AFTER insert ON `table_1` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');")
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_1_update` AFTER update ON `table_1` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');")
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_1_delete` AFTER delete ON `table_1` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');")
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_2_insert` AFTER insert ON `table_2` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_2');")
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_2_update` AFTER update ON `table_2` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_2');")
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_2_delete` AFTER delete ON `table_2` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_2');")
          # Catch unexpected queries, must go last.
          @connection.stub(:execute) do |value|
            raise "Unexpected query string: \"#{value}\""
          end

          @c.send(:add_triggers)
        end

        it "should not add triggers to the tracking table" do
          @connection.stub(:tables_from).with('database').and_return(['updated_tables', 'table_1', 'table_2'])
          @connection.tables_from('database').count.should == 3

          @connection.unstub(:execute)
          @connection.should_receive(:execute).with(/^\s*CREATE TRIGGER `database`.`table_1_/).exactly(3).times
          @connection.should_receive(:execute).with(/^\s*CREATE TRIGGER `database`.`table_2_/).exactly(3).times
          @connection.should_not_receive(:execute).with(/^\s*CREATE TRIGGER `database`.`updated_tables_/)
          @connection.stub(:execute) do |value|
            raise "Unexpected query string: \"#{value}\""
          end
          @c.send(:add_triggers)
        end
      end

      describe :add_triggers_to_table do
        it "should add triggers to a table" do
          @connection.unstub(:execute)

          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_1_insert` AFTER insert ON `table_1` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');")
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_1_update` AFTER update ON `table_1` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');")
          @connection.should_receive(:execute).with("CREATE TRIGGER `database`.`table_1_delete` AFTER delete ON `table_1` FOR EACH ROW INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');")
          @c.send(:add_triggers_to_table, 'database', 'table_1')
        end

        it "should handle ::Checkpointer::Database::DuplicateTriggerErrors" do
          @connection.should_receive(:execute).exactly(3).times.and_raise(::Checkpointer::Database::DuplicateTriggerError)
          @c.send(:add_triggers_to_table, 'database', 'table_1')
        end
      end

      describe :remove_triggers do
        it "should remove triggers from the database" do
          @connection.unstub(:execute)
          @connection.should_receive(:execute).with("DROP TRIGGER IF EXISTS `database`.`table_1_insert`;")
          @connection.should_receive(:execute).with("DROP TRIGGER IF EXISTS `database`.`table_1_update`;")
          @connection.should_receive(:execute).with("DROP TRIGGER IF EXISTS `database`.`table_1_delete`;")
          @connection.should_receive(:execute).with("DROP TRIGGER IF EXISTS `database`.`table_2_insert`;")
          @connection.should_receive(:execute).with("DROP TRIGGER IF EXISTS `database`.`table_2_update`;")
          @connection.should_receive(:execute).with("DROP TRIGGER IF EXISTS `database`.`table_2_delete`;")
          @c.send(:remove_triggers)
        end

        it "should not remove triggers from tracking table" do
          @connection.stub(:tables_from).with('database').and_return(['updated_tables', 'table_1', 'table_2'])
          @connection.tables_from('database').count.should == 3

          @connection.unstub(:execute)
          @connection.should_receive(:execute).with(/^DROP TRIGGER.*table_1/).exactly(3).times
          @connection.should_receive(:execute).with(/^DROP TRIGGER.*table_2/).exactly(3).times
          @connection.should_not_receive(:execute).with(/^DROP TRIGGER.*updated_tables/)
          @c.send(:remove_triggers)
        end
      end
    end

    # Test exceptional cases for ActiveRecord
    context "with ActiveRecord connection" do
    end

    # Test exceptional cases for Mysql2
    context "with Mysql2 connection" do
    end

  end
end