require 'spec/spec_helper.rb'

module ::Checkpointer::Database
  describe Mysql2Adapter do
    it_behaves_like 'a database adapter'

  #TODO
#   it 'should not instantiate without required parameters' do
#   options ={:host => 'localhost', :database => 'database', :username => 'root', :password => 'pass'}

#   # host is not required
#   test_options = options.reject{|key,value| key==:host}
#   expect { Checkpointer.new(test_options) }.to_not raise_error(ArgumentError)

#   # database is required
#   test_options = options.reject{|key,value| key==:database}
#   expect { Checkpointer.new(test_options) }.to raise_error(ArgumentError)

#   # username is required
#   test_options = options.reject{|key,value| key==:username}
#   expect { Checkpointer.new(test_options) }.to raise_error(ArgumentError)

#   # password is not required
#   test_options = options.reject{|key,value| key==:password}
#   expect { Checkpointer.new(test_options) }.to_not raise_error(ArgumentError)
# end

# it 'should instantiate with standard connection parameters' do
#   options ={:host => 'localhost', :database => 'database', :username => 'root', :password => 'pass'}
#   c = Checkpointer.new(options)
#   # Connection instantiation is lazy, therefore we don't check if Mysql2::Client is called here.
#   c.should be_kind_of(Checkpointer)
# end

  end
end
