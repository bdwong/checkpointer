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

      # Escape a generic expression. No quotes added.
      def escape(value)
      end

      # Properly escape and quote an identifier such as database, table or column name.
      def identifier(value)
      end

      # Properly escape and quote a string literal.
      def literal(value)
      end

      # List tables from a database
      def tables_from(db=current_database)
      end

      # Get the create statement to create a given table.
      def show_create_table(db, table)
      end

      # Normalize result of single-column queries into an array.
      def normalize_result(result)
      end
    end
  end
end