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
        result.to_a[0].values[0]
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

      # Escape a generic expression. No quotes added.
      def escape(value)
        @connection.escape(value)
      end

      # Properly escape and quote an identifier such as database, table or column name.
      def identifier(value)
        "\`#{value.gsub('`', '``')}\`"
      end

      # Properly escape and quote a string literal.
      def literal(value)
        "'#{escape(value)}'"
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
          create_sql = @connection.query("SHOW CREATE TABLE #{identifier(db)}.#{identifier(table)}")
          create_sql.first["Create Table"]
        rescue Mysql2::Error => e
          raise unless e.message =~ /^Table.*doesn't exist$/
          return nil
        end
      end

      # Normalize result of single-column queries into an array.
      def normalize_result(result)
        column_values(result)
      end

      # Return a column of values from a query result as an array
      def column_values(result, column=0)
        if column.kind_of?(Fixnum)
          column = result.fields[column]
          return nil if column.nil?
        else
          return nil unless result.fields.include?(column)
        end
        result.map{|h| h[column]}.flatten
      end
    end
  end
end