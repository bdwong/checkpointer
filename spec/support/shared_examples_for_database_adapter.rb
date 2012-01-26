shared_examples "a database adapter" do
  it 'should respond to configured?' do
    described_class.should respond_to :configured?
  end

  it 'should accept options hash on new' do
    expect { described_class.new({}) }.to_not raise_error(ArgumentError)
  end

  it 'should respond to common methods' do
    should respond_to :current_database
    should respond_to :connection
    should respond_to :close_connection
    should respond_to(:escape).with(1).argument
    should respond_to(:execute).with(1).argument
  end
end
