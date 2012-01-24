class DatabaseCopier
  def self.sql_connection
    ActiveRecord::Base.connection
  end

  def self.create_database(db)
    sql_connection.execute("DROP DATABASE IF EXISTS #{db}")
    sql_connection.execute("CREATE DATABASE #{db} CHARACTER SET utf8 COLLATE utf8_general_ci")
  end

  def self.copy_database(from_db, to_db)
    sql_connection.execute("DROP DATABASE IF EXISTS #{to_db}")
    sql_connection.execute("CREATE DATABASE #{to_db} CHARACTER SET utf8 COLLATE utf8_general_ci")

    tables = sql_connection.select_all("SHOW TABLES FROM #{from_db}")
    #the results are an array of hashes, ie:
    # [{"table_from_customerdb1" => "customers"},{"table_from_customerdb1" => "employees},...]
    table_names = tables.map{|h| h.values}.flatten

    copy_tables(table_names, from_db, to_db)
  end

  def self.copy_tables(table_names, from_db, to_db)
    return if table_names.empty?
    
    # For efficiency, turn off time consuming options.
    sql_connection.execute("set autocommit = 0;")
    sql_connection.execute("set unique_checks = 0;")
    sql_connection.execute("set foreign_key_checks = 0;")

    table_names.each { |name| 
      print "."
      # Think about whether we should drop/create/re-add triggers, or just truncate.
      sql_connection.execute("CREATE TABLE IF NOT EXISTS #{to_db}.#{name} LIKE #{from_db}.#{name}")
      sql_connection.execute("TRUNCATE TABLE #{to_db}.#{name}")
      sql_connection.execute("INSERT INTO #{to_db}.#{name} SELECT * FROM #{from_db}.#{name}")
    }

    sql_connection.execute("COMMIT;")
    sql_connection.execute("set foreign_key_checks = 1;")
    sql_connection.execute("set unique_checks = 1;")
    sql_connection.execute("set autocommit = 1;")
  end
end
