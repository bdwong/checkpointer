require 'spec/spec_helper.rb'

# Fake out ActiveRecord for testing.
module ActiveRecord
  if not const_defined?(:ConnectionNotEstablished)
    class ConnectionNotEstablished < Exception; end
  end
end

module Checkpointer
  describe Checkpointer do
    describe :active_record_connection? do
      it 'should return false if ActiveRecord is not loaded' do
        Checkpointer.active_record_connection?.should be_false
      end

      it 'should return true if ActiveRecord connection is present' do
        active_record_base = double('ActiveRecord::Base')
        active_record_base.stub(:connection).and_return(true)
        Checkpointer.stub(:active_record_base).and_return(active_record_base)

        Checkpointer.active_record_connection?.should be_true
      end

      it 'should return false if ActiveRecord is loaded but connection is not made' do
        active_record_base = double('ActiveRecord::Base')
        active_record_base.stub(:connection) { raise ActiveRecord::ConnectionNotEstablished }
        Checkpointer.stub(:active_record_base).and_return(active_record_base)

        Checkpointer.active_record_connection?.should be_false
      end
    end

    # ActiveRecord::Base.connection is not nil
    context "with ActiveRecord and connection" do
      before(:each) do
        Checkpointer.stub(:active_record_connection?).and_return(true)
        #Checkpointer.any_instance.stub(:current_database).and_return('database')

        @raw_connection = double()
        @raw_connection.stub(:kind_of?).with(Mysql2::Client).and_return(true) #TODO test for this.
        @raw_connection.stub(:query).with('SELECT DATABASE();').and_return([['database']])

        Checkpointer.stub_chain(:active_record_base, :connection, :raw_connection).and_return(@raw_connection)
      end

      it 'should raise ArgumentError when instantiating with no parameters' do
        expect { Checkpointer.new }.to raise_error(ArgumentError)
      end

      # it 'should instantiate with string parameter' do
      # 	c = Checkpointer.new('database')
      #   c.should be_kind_of(Checkpointer)
      # end

      it 'should instantiate with empty hash' do
        c = Checkpointer.new({})
        c.should be_kind_of(Checkpointer)
      end

      it 'should instantiate with :database value from hash' do
        #Checkpointer.expect(:method_call).with({:database => 'other_database'})
        #Mysql2::Client.new(options) # Set expectation here.
        c = Checkpointer.new(:database => 'other_database')
        c.should be_kind_of(Checkpointer)
      end
    end

    context "with ActiveRecord and no connection" do
      before(:each) do
        Checkpointer.stub(:active_record_connection?).and_return(false)
        #Checkpointer.any_instance.stub(:current_database).and_return('database')

        @raw_connection = double()
        @raw_connection.stub(:kind_of?).with(Mysql2::Client).and_return(true) #TODO test for this.
        @raw_connection.stub(:query).with('SELECT DATABASE();').and_return([['database']])

        Checkpointer.stub_chain(:active_record_base, :connection) do
          raise ActiveRecord::ConnectionNotEstablished
        end
      end

      it 'should not instantiate with empty hash' do
        expect { Checkpointer.new({}) }.to raise_error(ArgumentError)
      end
    end

    context "without ActiveRecord" do
      before(:each) do
        Checkpointer.stub(:active_record_connection?).and_return(false)
      end
      # it 'should not instantiate with string parameter' do
      #   expect { Checkpointer.new('database') }.to raise_error(RuntimeError)
      # end

      it 'should not instantiate without required parameters' do
        options ={:host => 'localhost', :database => 'database', :username => 'root', :password => 'pass'}

        # host is not required
        test_options = options.reject{|key,value| key==:host}
        expect { Checkpointer.new(test_options) }.to_not raise_error(ArgumentError)

        # database is required
        test_options = options.reject{|key,value| key==:database}
        expect { Checkpointer.new(test_options) }.to raise_error(ArgumentError)

        # username is required
        test_options = options.reject{|key,value| key==:username}
        expect { Checkpointer.new(test_options) }.to raise_error(ArgumentError)

        # password is not required
        test_options = options.reject{|key,value| key==:password}
        expect { Checkpointer.new(test_options) }.to_not raise_error(ArgumentError)
      end

      # it 'should not instantiate with only :database value from hash' do
      #   options = {:database => 'database'}
      #   #Mysql2::Client.should_receive(:new).and_raise(Mysql2::Error.new("Access denied")) # Access denied #.with(options)
      #   expect { Checkpointer.new(options) }.to raise_error(Mysql2::Error)
      #   #Checkpointer.new(options)
      # end

      # it 'should not instantiate with only :username value from hash' do
      #   #expect { Checkpointer.new(:database => 'database') }.to raise_error(RuntimeError)
      #   #Mysql2::Client.should_receive(:new) #.with(options)
      #   #Mysql2::Client.any_instance.should_receive(:initialize)
      #   options = {:username => 'me'}
      #   #Mysql2::Client.stub(:new) { raise Mysql2::Error.new }
      #   Mysql2::Client.should_receive(:new).with(options).and_raise(Mysql2::Error.new("Access denied"))
      #   expect { Checkpointer.new(options) }.to raise_error(Mysql2::Error)
      # end

      it 'should instantiate with standard connection parameters' do
        options ={:host => 'localhost', :database => 'database', :username => 'root', :password => 'pass'}
        c = Checkpointer.new(options)
        # Connection instantiation is lazy, therefore we don't check if Mysql2::Client is called here.
        c.should be_kind_of(Checkpointer)
      end
    end

  end
end