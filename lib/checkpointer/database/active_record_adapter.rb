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