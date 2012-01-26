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
    #include ::Checkpointer::Database

    before(:each) do
      ::Checkpointer::Checkpointer.any_instance.stub(:autodetect_database_adapter).and_return(DummyAdapter)
    end

    # Test most of the functionality with database mocks.
    context "with dummy connection" do
      it "instantiates" do
        c = Checkpointer.new
        c.should be_kind_of(Checkpointer)
        c.sql_connection.should be_kind_of(DummyAdapter)
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