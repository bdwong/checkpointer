module Checkpointer
  require 'mysql2'

  class DatabaseCopier
    include ::Checkpointer::Database

    def self.from_connection(connection)
      return DatabaseCopier.new(:connection => connection)
    end

    def initialize(options = {})
      connection = options.delete(:connection)
      if connection
        @db_adapter = connection
      else
        @db_adapter = autodetect_database_adapter.new(options)
      end
    end

    def sql_connection
      @db_adapter
    end

    def create_database(db)
      sql_connection.execute("DROP DATABASE IF EXISTS #{sql_connection.identifier(db)}")
      sql_connection.execute("CREATE DATABASE IF NOT EXISTS #{sql_connection.identifier(db)} CHARACTER SET utf8 COLLATE utf8_general_ci")
    end

    def create_database_for_copy(from_db, to_db)
      sql_connection.execute("CREATE DATABASE IF NOT EXISTS #{sql_connection.identifier(to_db)} CHARACTER SET utf8 COLLATE utf8_general_ci")
      drop_tables_not_in_source(from_db, to_db)
    end

    def drop_tables_not_in_source(from_db, to_db)
      from_tables = sql_connection.tables_from(from_db)
      to_tables = sql_connection.tables_from(to_db)
      to_escaped = sql_connection.identifier(to_db)
      (to_tables - from_tables).each do |tbl|
        sql_connection.execute("DROP TABLE #{to_escaped}.#{sql_connection.identifier(tbl)}")
      end
    end

    def copy_database(from_db, to_db)
      create_database_for_copy(from_db, to_db)
      tables = sql_connection.tables_from(from_db)
      copy_tables(tables, from_db, to_db)
    end

    def show_create_table_without_increment(db, table)
      create_sql = sql_connection.show_create_table(db, table)
      if not create_sql.nil?
        matches = create_sql.match(/\sAUTO_INCREMENT=([0-9]+)/)
        if matches.nil?
          auto_increment = 0
        else
          auto_increment = matches[1]
        end
        create_sql.gsub!(/\s+AUTO_INCREMENT=[0-9]+\s*/," ") # Remove auto-increment
        return [create_sql, auto_increment]
      else
        return [nil, 0]
      end
    end

    # Copy tables table_names from from_db to to_db.
    #
    # If a block is present, it is executed after each table is prepared but before
    # it is populated with data, with |tbl, op|, where:
    # * tbl is the blank table
    # * op is the operation used to create the table, one of :create, :truncate, :drop_and_create
    def copy_tables(table_names, from_db, to_db)
      return if table_names.empty?
      
      # For efficiency, turn off time consuming options.
      sql_connection.execute("set autocommit = 0;")
      sql_connection.execute("set unique_checks = 0;")
      sql_connection.execute("set foreign_key_checks = 0;")

      from_escaped = sql_connection.identifier(from_db)
      to_escaped = sql_connection.identifier(to_db)

      table_names.each { |name| 
        print "."
        # Think about whether we should drop/create/re-add triggers, or just truncate.
        tbl = sql_connection.identifier(name)

        to_create, to_autoincr = show_create_table_without_increment(to_db, name)
        from_create, from_autoincr = show_create_table_without_increment(from_db, name)

        if to_create.nil?
          # table doesn't exist, create it.
          op = :create
          sql_connection.execute("CREATE TABLE IF NOT EXISTS #{to_escaped}.#{tbl} LIKE #{from_escaped}.#{tbl}")
        elsif from_create == to_create
          # table is the same, truncate it.
          op = :truncate
          sql_connection.execute("TRUNCATE TABLE #{to_escaped}.#{tbl}")
        else
          # table is different, drop and create.
          op = :drop_and_create
          sql_connection.execute("DROP TABLE #{to_escaped}.#{tbl}")
          sql_connection.execute("CREATE TABLE IF NOT EXISTS #{to_escaped}.#{tbl} LIKE #{from_escaped}.#{tbl}")
        end

        if block_given?
          yield tbl, op
        end

        sql_connection.execute("INSERT INTO #{to_escaped}.#{tbl} SELECT * FROM #{from_escaped}.#{tbl}")
        #
        # if from_create == to_create and from_autoincr != to_autoincr
        #   puts "Warning: set auto_increment not implemented yet."
            # For many purposes it won't matter because TRUNCATE TABLE
            # will reset auto_increment (see docs for TRUNCATE TABLE).
            # If it does matter then either implement this or
            # provide an option to drop the table.
        # end

      }

      sql_connection.execute("COMMIT;")
      sql_connection.execute("set foreign_key_checks = 1;")
      sql_connection.execute("set unique_checks = 1;")
      sql_connection.execute("set autocommit = 1;")
    end
  end
end
