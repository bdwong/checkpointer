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
        # TODO
        # @connection = Checkpointer.active_record_base.connection
        # if not @connection.raw_connection.kind_of?(Mysql2::Client)
        #   raise RuntimeError.new('Checkpointer only works with Mysql2 client on ActiveRecord.')
        # end
        
      end

      def current_database
        result = execute('SELECT DATABASE();')
        return nil if result.count==0
        result.to_a[0][0]
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