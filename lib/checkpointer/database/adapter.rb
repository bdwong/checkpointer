module Checkpointer
  module Database
  	class Adapter
      def self.configured?
        false
      end

      def initialize(options={})
      end

      def connection
      end

      def close_connection
      end

      def execute(query)
      end

      def escape(value)
      end
  	end
  end
end