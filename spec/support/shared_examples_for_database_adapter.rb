
# A configured database adapter can be instantiated with no parameters.
shared_examples "a configured database adapter" do
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
    should respond_to(:identifier).with(1).argument
    should respond_to(:literal).with(1).argument
    should respond_to(:execute).with(1).argument
    should respond_to(:tables_from).with(1).argument
    should respond_to(:show_create_table).with(2).arguments
    should respond_to(:normalize_result).with(1).argument
  end
end

# An unconfigured database adapter can be instantiated with additional parameters.
shared_examples "an unconfigured database adapter" do
  it 'should respond to configured?' do
    described_class.should_not be_configured
  end
end