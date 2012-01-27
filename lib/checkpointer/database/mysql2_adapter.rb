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
        begin
          @connection.query(query)
        rescue Mysql2::Error => e
          raise unless e.message =~ /multiple triggers/
          raise ::Checkpointer::Database::DuplicateTriggerError.new('Unhandled duplicate trigger')
        end
      end

      def escape(value)
        @connection.escape(value)
      end

      # Normalize result of single-column queries into an array.
      def normalize_result(result)
        result.map{|h| h.values}.flatten
      end
    end
  end
end