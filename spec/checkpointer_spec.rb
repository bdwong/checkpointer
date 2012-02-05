require 'spec/spec_helper.rb'

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
        pending
      end

      describe :checkpoint do
        pending
      end

      describe :restore do
        pending
      end

      describe :pop do
        pending
      end

      describe :drop do
        pending
      end

      describe :drop_checkpoint_number do
        pending
      end

      describe :drop_checkpoint_name do
        pending
      end

      describe :checkpoints do
        pending
      end

      describe :backup do
        pending
      end

      describe :restore_all do
        pending
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
        it "should list all records in the tracking table plus the tracking table" do
          @connection.unstub(:execute)
          # We shouldn't have to stub normalize_result here... refactoring needed.
          @connection.stub(:normalize_result) {|value| value}

          @connection.should_receive(:execute).with('SELECT name FROM `database`.`updated_tables`').
            and_return(['table_1'])
          @c.send(:changed_tables_from, 'database').should == ['table_1', 'updated_tables']
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

          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_1_insert` AFTER insert \
            ON `table_1` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');
          EOF
          )
          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_1_update` AFTER update \
            ON `table_1` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');
          EOF
          )
          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_1_delete` AFTER delete \
            ON `table_1` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');
          EOF
          )
          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_2_insert` AFTER insert \
            ON `table_2` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_2');
          EOF
          )
          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_2_update` AFTER update \
            ON `table_2` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_2');
          EOF
          )
          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_2_delete` AFTER delete \
            ON `table_2` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_2');
          EOF
          )
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

          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_1_insert` AFTER insert \
            ON `table_1` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');
          EOF
          )
          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_1_update` AFTER update \
            ON `table_1` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');
          EOF
          )
          @connection.should_receive(:execute).with(<<-EOF
          CREATE TRIGGER `database`.`table_1_delete` AFTER delete \
            ON `table_1` FOR EACH ROW \
            INSERT IGNORE INTO `database`.`updated_tables` VALUE ('table_1');
          EOF
          )
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