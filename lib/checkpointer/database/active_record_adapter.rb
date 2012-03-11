module Checkpointer
  module Database
  	class ActiveRecordAdapter < Adapter
      def self.configured?
        has_active_record? and has_active_record_connection?
      end

      def self.has_active_record?
        begin
          ActiveRecord::Base
        rescue NameError # NameError: uninitialized constant ActiveRecord
          return false
        end
        true
      end

      def self.has_active_record_connection?
        begin
          return true if not ActiveRecord::Base.connection.nil?
        rescue ActiveRecord::ConnectionNotEstablished
          return false
        end
      end

      def initialize(options={})
        # TODO
        @connection = ActiveRecord::Base.connection
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
        @connection
      end

      def close_connection #disconnect
        connection.disconnect!
      end

      def execute(query)
        begin
          connection.execute(query)
        rescue ::ActiveRecord::StatementInvalid => e
          case
          when e.message =~ /multiple triggers/
            raise ::Checkpointer::Database::DuplicateTriggerError.new('Unhandled duplicate trigger')
          when e.message =~ /^Mysql2::Error: Unknown database/
            raise ::Checkpointer::Database::DatabaseNotFoundError.new('Database not found')
          else
            raise
          end
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

      # Get the create statement to create a given table.
      # Return nil if the table doesn't exist.
      def show_create_table(db, table)
        begin
          to_create = connection.execute("SHOW CREATE TABLE #{identifier(db)}.#{identifier(table)}")
          to_create = to_create.first[1] # ActiveRecord
        rescue ActiveRecord::StatementInvalid => e
          raise unless e.message =~ /Table.*doesn't exist/
          return nil
        end
      end
      
      # Normalize result of single-column queries into an array.
      def normalize_result(result)
        #result.to_a.flatten
        column_values(result)
      end

      # Return a column of values from a query result as an array
      def column_values(result, column=0)
        if column.kind_of?(Fixnum)
          return nil if result.fields[column].nil?
        else
          column = result.fields.index(column)
          return nil if column.nil?
        end

        result.map{|h| h[column]}
      end

  	end
  end
end