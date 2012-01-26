module Checkpointer
  module Database
    class Mysql2Adapter < Adapter
      def self.configured?
        true
      end

      def initialize(options={})
        @connection = Mysql2::Client.new(options)
      end

      def current_database
        result = execute('SELECT DATABASE();')
        return nil if result.count==0
        result.to_a[0][0]
      end

      def connection
        @connection
      end

      def close_connection #disconnect
        @connection.close
      end

      def execute(query)
        @connection.query(query)
      end

      def escape(value)
        @connection.escape(value)
      end

      # TODO
      # if connection_options_specified? 
      #   raise ArgumentError.new('Missing required option') unless has_required_options?
      #   @connection = Mysql2::Client.new(@options)


    end
  end
end