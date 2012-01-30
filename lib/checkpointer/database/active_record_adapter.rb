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
        @connection = active_record_base.connection
        # if not @connection.raw_connection.kind_of?(Mysql2::Client)
        #   raise RuntimeError.new('Checkpointer only works with Mysql2 client on ActiveRecord.')
        # end
        
      end

      def active_record_base
        ActiveRecordAdapter.active_record_base
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
        connection.disconnect!
      end

      def execute(query)
        begin
          connection.execute(query)
        rescue ::ActiveRecord::StatementInvalid => e
          raise unless e.message =~ /multiple triggers/
          raise ::Checkpointer::Database::DuplicateTriggerError.new('Unhandled duplicate trigger')
        end
      end

      # Escape a generic expression. No quotes added.
      def escape(value)
        connection.quote_string(value)
      end

      # Properly escape and quote an identifier such as database, table or column name.
      def identifier(value)
        connection.quote_table_name(value)
      end

      # Properly escape and quote a string literal.
      def literal(value)
        connection.quote(value)
      end      

      # List tables from a database
      def tables_from(db=current_database)
        result = execute("SHOW TABLES FROM #{identifier(db)}")
        normalize_result(result)
      end

      # Normalize result of single-column queries into an array.
      def normalize_result(result)
        result.to_a.flatten
      end

  	end
  end
end