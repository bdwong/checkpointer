require 'spec/spec_helper.rb'

# Fake out ActiveRecord for testing.
module ActiveRecord
  if not const_defined?(:ConnectionNotEstablished)
    class ConnectionNotEstablished < Exception; end
  end
end

module ::Checkpointer::Database
  describe ActiveRecordAdapter do

    describe 'self.configured?' do
      it 'should return true if both ActiveRecord and its connection are configured.' do
        active_record_base = double('ActiveRecord::Base')
        active_record_base.stub(:connection).and_return(true)
        described_class.stub(:active_record_base => active_record_base)

        described_class.should be_configured
      end

      it 'should return false if ActiveRecord is not loaded' do
        described_class.stub(:active_record_base).and_raise(NameError.new('uninitialized constant ActiveRecord'))

        described_class.should_not be_configured
      end

      it 'should return false if ActiveRecord is loaded but the connection is not configured' do
        active_record_base = double('ActiveRecord::Base')
        active_record_base.stub(:connection).and_raise(ActiveRecord::ConnectionNotEstablished.new('Connection not established'))
        described_class.stub(:active_record_base => active_record_base)

        described_class.should_not be_configured
      end
    end

    describe 'self.has_active_record?' do
      it 'should return true if ActiveRecord is found' do
        active_record_base = double('ActiveRecord::Base')
        described_class.stub(:active_record_base => active_record_base)

        described_class.should have_active_record
      end

      it 'should return false if ActiveRecord is not found' do
        described_class.stub(:active_record_base).and_raise(NameError.new('uninitialized constant ActiveRecord'))

        described_class.should_not have_active_record
      end
    end

    describe 'self.has_active_record_connection?' do
      it 'should return true if ActiveRecord has a connection' do
        active_record_base = double('ActiveRecord::Base')
        active_record_base.stub(:connection).and_return(true)
        described_class.stub(:active_record_base => active_record_base)

        described_class.should have_active_record_connection
      end

      it 'should return false if ActiveRecord has no connection' do
        active_record_base = double('ActiveRecord::Base')
        active_record_base.stub(:connection).and_raise(ActiveRecord::ConnectionNotEstablished.new('Connection not established'))
        described_class.stub(:active_record_base => active_record_base)

        described_class.should_not have_active_record_connection
      end
    end

  end
end