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
      end

      describe :sql_connection do
        it "has sql_connection DummyAdapter" do
          @c.sql_connection.should be_kind_of(DummyAdapter)
        end
      end

      describe :tracking_table do
        subject == "updated_tables"
      end

      describe :track do
        pending
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
    end

    # Test exceptional cases for ActiveRecord
    context "with ActiveRecord connection" do
    end

    # Test exceptional cases for Mysql2
    context "with Mysql2 connection" do
    end

  end
end