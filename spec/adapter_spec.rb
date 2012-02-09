require File.dirname(__FILE__) + '/spec_helper.rb'

module ::Checkpointer::Database
  describe Adapter do
    it_behaves_like 'a configured database adapter'
  end

  describe :configured? do
    it 'should not be configured because it is an abstract class' do
      Adapter.should_not be_configured
    end
  end

end