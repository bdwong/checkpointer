require 'spec/spec_helper.rb'

module Checkpointer
  describe DatabaseCopier do
    context "instantiation" do
      it "should create instantiate a database adapter as the connection" do
        adapter_instance = double("adapter_instance")
        mock_adapter = double(:new => adapter_instance)
        DatabaseCopier.any_instance.stub(:autodetect_database_adapter).and_return(mock_adapter)

        d = DatabaseCopier.new
        d.sql_connection.should == adapter_instance
      end
    end
  end
end