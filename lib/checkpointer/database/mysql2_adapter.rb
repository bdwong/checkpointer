module Checkpointer
  module Database
    class Mysql2Adapter < Adapter
      def initialize(options={})
        @connection = Mysql2::Client.new(options)
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
    end
  end
end