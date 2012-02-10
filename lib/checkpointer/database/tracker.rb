module Checkpointer
  module Database
    class Tracker
      def initialize(adapter, name)
        @db_adapter = adapter
        @db_name = name
      end

      def sql_connection
        @db_adapter
      end

      def tracking_table
        "updated_tables"
      end

      # Backup the database and create monitoring triggers
      def track
        drop_tracking_table
        create_tracking_table
        add_triggers
      end

      # Delete monitoring triggers
      def untrack
        remove_triggers
        drop_tracking_table
      end

      def tables_from(db)
        result = sql_connection.tables_from(db)
        # Ensure tracking table is last, if present.
        if result.include?(tracking_table)
          result = (result-[tracking_table]) << tracking_table
        end
        result
      end

      # Select table names from tracking table
      def changed_tables_from(db)
        result = sql_connection.execute("SELECT name FROM #{sql_connection.identifier(db)}.#{sql_connection.identifier(tracking_table)}")
        sql_connection.normalize_result(result)
      end

      def create_tracking_table
        db = sql_connection.identifier(@db_name)
        tbl = sql_connection.identifier(tracking_table)
        sql_connection.execute("CREATE TABLE IF NOT EXISTS #{db}.#{tbl}(name char(64), PRIMARY KEY (name));")
        #sql_connection.execute("CREATE TABLE IF NOT EXISTS #{db}.#{tbl}(name char(64), PRIMARY KEY (name)) ENGINE = MEMORY;")
      end

      def drop_tracking_table
        db = sql_connection.identifier(@db_name)
        tbl = sql_connection.identifier(tracking_table)
        sql_connection.execute("DROP TABLE IF EXISTS #{db}.#{tbl};")
      end

      # Add triggers to all tables except tracking table
      def add_triggers
        puts "Adding triggers, this could take a while..."
        tables = tables_from(@db_name)
        tables.reject{|r| r==tracking_table}.each do |t|
          add_triggers_to_table(@db_name, t)
        end
        puts "Triggers added."
      end

      # Add triggers to an individual table.
      # db_name: unescaped database name
      # table: unescaped table name
      def add_triggers_to_table(db_name, table)
        db = sql_connection.identifier(db_name)
        tbl_value = sql_connection.literal(table)
        tbl_identifier = sql_connection.identifier(table)
        track_tbl = sql_connection.identifier(tracking_table)
        print "t"
        ["insert", "update", "delete"].each do |operation|
          trigger_name = sql_connection.identifier("#{table}_#{operation}")
          cmd = <<-EOF
CREATE TRIGGER #{db}.#{trigger_name} AFTER #{operation} \
  ON #{tbl_identifier} FOR EACH ROW \
  INSERT IGNORE INTO #{db}.#{track_tbl} VALUE (#{tbl_value});
EOF
          begin
            sql_connection.execute(cmd)
          rescue ::Checkpointer::Database::DuplicateTriggerError
            # Triggers already installed.
          end
        end
      end

        # Remove triggers from all tables except tracking table
      def remove_triggers
        puts "Removing triggers, this could take a while..."

        # Init repeated variables outside the loop
        db = sql_connection.identifier(@db_name)

        tables = tables_from(@db_name)
        tables.reject{|r| r==tracking_table}.each do |t|
          print "u"
          ["insert", "update", "delete"].each do |operation|
            trigger_name = sql_connection.identifier("#{t}_#{operation}")
            cmd = "DROP TRIGGER IF EXISTS #{db}.#{trigger_name};"
            sql_connection.execute(cmd)
          end
        end
        puts "Triggers removed."
      end

    end
  end
end
