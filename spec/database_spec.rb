require File.dirname(__FILE__) + '/spec_helper.rb'

class SUT
  include ::Checkpointer::Database
end

module Checkpointer
  describe :autodetect_database_adapter do
    before(:each) do
      @adapter1 = double('Adapter1', :configured? => false)
      @adapter2 = double('Adapter2', :configured? => false)
      @instance = SUT.new
      @instance.stub(:database_adapters => [@adapter1, @adapter2]) #
    end

    it 'should raise RuntimeError if no adapters are configured' do
      expect { @instance.autodetect_database_adapter }.to raise_error(RuntimeError)
    end

    it 'should return the first adapter if it is configured' do
      @adapter1.should_receive(:configured?).and_return(true)
      @instance.autodetect_database_adapter #.should == @adapter1
    end

    it 'should return the second adapter if it is configured' do
      @adapter2.should_receive(:configured?).and_return(true)
      @instance.autodetect_database_adapter.should == @adapter2
    end

  end

  describe :database_adapters do
    it "should return supported database adapters" do
      @instance = SUT.new
      @instance.database_adapters.should == [Database::ActiveRecordAdapter, Database::Mysql2Adapter]
    end
  end
end