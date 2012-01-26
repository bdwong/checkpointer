module Checkpointer
  module Database
  	class ActiveRecordAdapter < Adapter
      def self.configured?
        has_active_record? and has_active_record_connection?
      end

      # Override this for testing.
      def self.active_record_base
        ActiveRecord::Base
      end

      def self.has_active_record?
        begin
          active_record_base
        rescue NameError # NameError: uninitialized constant ActiveRecord
          return false
        end
        true
      end

      def self.has_active_record_connection?
        begin
          return true if not active_record_base.connection.nil?
        rescue ActiveRecord::ConnectionNotEstablished
          return false
        end
      end

      def initialize(options={})
      end

      def connection
        ActiveRecord::Base.connection
      end

      def close_connection #disconnect
        connection.disconnect!
      end

      def execute(query)
        connection.execute(query)
      end

      def escape(value)
        ActiveRecord::Base.quote_value(value)
      end
  	end
  end
end