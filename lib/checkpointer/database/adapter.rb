module Checkpointer
  module Database
    class Adapter
      def self.configured?
        false
      end

      def initialize(options={})
      end

      def current_database
      end

      def connection
      end

      def close_connection
      end

      def execute(query)
      end

      def escape(value)
      end

      # Normalize result of single-column queries into an array.
      def normalize_result(result)
      end
    end
  end
end