module Checkpointer
  require 'mysql2'

  class Checkpointer
    include ::Checkpointer::Database

    def initialize(options={})
      @options = options.to_hash
      adapter = autodetect_database_adapter
      #puts "Adapter found: #{adapter}"
      @db_adapter = adapter.new(options)
      @checkpoint_number=0
      @last_checkpoint=0
      @db_name = options[:database] || @db_adapter.current_database

      raise ArgumentError.new("No database name specified or no database selected.") if @db_name.nil?
      @db_backup =  options[:backup] || "#{@db_name}_backup"
      @tracker = ::Checkpointer::Database::Tracker.new(@db_adapter, @db_name)
    end

    def sql_connection
      @db_adapter
    end

    def database
      @db_name
    end

    # Backup the database and create monitoring triggers
    def track
      @tracker.track
      backup
    end

    # Delete monitoring triggers
    def untrack
      @tracker.untrack
    end

    # Checkpoint behavior
    # checkpoint(no name) should +1 the checkpoint number.
    # checkpoint(name) should checkpoint that name.
    # checkpoint(number) should fail with an error..
    def checkpoint(cp=nil)
      raise ArgumentError.new("Manual checkpoints cannot be a number.") if is_number?(cp)

      # Backup all changed tables.
      table_names = changed_tables_from(@db_name) << @tracker.tracking_table
      if cp.nil?
        @checkpoint_number += 1
        cp = @checkpoint_number
      end
      db_checkpoint = "#{@db_backup}_#{cp}"
      db_copier = DatabaseCopier.from_connection(@db_adapter)
      db_copier.create_database_for_copy(@db_name, db_checkpoint)
      db_copier.copy_tables(table_names, @db_name, db_checkpoint)
      @last_checkpoint = cp
    end

    # Checkpoint 0 is the base backup.
    def restore(cp=@last_checkpoint)
      checkpoint_tables=[]
      if cp != 0
        db_checkpoint = "#{@db_backup}_#{cp}"
        checkpoint_tables = tables_from(db_checkpoint)
      end

      # Get all changed tables.
      changed_tables = changed_tables_from(@db_name)
      # puts "checkpoint tables: #{checkpoint_tables.inspect}"
      # puts "changed tables: #{changed_tables.inspect}"
      # puts "difference: #{(changed_tables - checkpoint_tables).inspect}"

      # Restore tables not in the checkpoint from backup
      db_copier = DatabaseCopier.from_connection(@db_adapter)
      db_copier.copy_tables(changed_tables - checkpoint_tables, @db_backup, @db_name) do |tbl, op|
        add_triggers_to_table(@db_name, tbl) if [:drop_and_create, :create].include?(op)
      end
      
      # Restore tables from checkpoint.
      # This must come last because the tracking table must be restored last,
      # otherwise triggers will update the tracking table incorrectly.
      db_copier.copy_tables(checkpoint_tables, db_checkpoint, @db_name) do |tbl, op|
        add_triggers_to_table(@db_name, tbl) if [:drop_and_create, :create].include?(op)
      end

      @checkpoint_number = cp if is_number?(cp)
      @last_checkpoint = cp
    end

    # Restore the highest-number checkpoint and drop it.
    def pop
      if restore(@checkpoint_number) > 0
        drop
      end
    end

    # Drop all checkpoints at or above the current number, then reduce the current checkpoint number.
    def drop(cp=@checkpoint_number)
      if is_number?(cp)
        drop_checkpoint_number(cp)
      else
        drop_checkpoint_name(cp)
      end
    end

    def drop_checkpoint_number(cpnum)
      @checkpoint_number = cpnum
      checkpoints.each do |cp|
        if is_number?(cp) and cp.to_i >= @checkpoint_number
          puts "Dropping checkpoint #{cp}."
          db = sql_connection.identifier("#{@db_backup}_#{cp}")
          sql_connection.execute("DROP DATABASE #{db}")
        end
      end
      @checkpoint_number -= 1 unless @checkpoint_number == 0
      @last_checkpoint = @checkpoint_number unless not is_number?(@last_checkpoint)
    end

    def drop_checkpoint_name(cpname)
      if not checkpoints.include?(cpname.to_s)
        puts "Checkpoint #{cpname} not found."
        return
      end
      puts "Dropping checkpoint #{cpname}."
      db = sql_connection.identifier("#{@db_backup}_#{cpname}")
      sql_connection.execute("DROP DATABASE #{db}")
      if @last_checkpoint == cpname
        @last_checkpoint = @checkpoint_number
      end
      @last_checkpoint
    end


    # List checkpoints found by the database engine.
    def checkpoints
      db_pattern = "#{sql_connection.escape(@db_backup)}".gsub("_", "\\_").gsub("%", "\\%")
      # TODO: this should be quoted properly.
      result = sql_connection.execute("SHOW DATABASES LIKE '#{db_pattern}\\_%'")
      prefix_length = @db_backup.length+1
      sql_connection.normalize_result(result).map {|db| db[prefix_length..-1] }
    end

    def backup
      db_copier = DatabaseCopier.from_connection(@db_adapter)
      db_copier.copy_database(@db_name, @db_backup)
    end

    def restore_all
      tables = tables_from(@db_backup)
      db_copier = DatabaseCopier.from_connection(@db_adapter)
      db_copier.drop_tables_not_in_source(@db_backup, @db_name)
      db_copier.copy_tables(tables, @db_backup, @db_name) do |tbl, op|
        add_triggers_to_table(@db_name, tbl) if [:drop_and_create, :create].include?(op)
      end
      # Ensure tracking table
      create_tracking_table
    end

    private
    def is_number?(value)
      value.kind_of?(Fixnum) or (value.respond_to?(:to_i) and value.to_i.to_s == value)
    end

    def tables_from(db)
      @tracker.tables_from(db)
    end

    # Select table names from tracking table
    def changed_tables_from(db)
      @tracker.changed_tables_from(db)
    end

    def create_tracking_table
      @tracker.create_tracking_table
    end

    # Add triggers to an individual table.
    # db_name: unescaped database name
    # table: unescaped table name
    def add_triggers_to_table(db_name, table)
      @tracker.add_triggers_to_table(db_name, table)
    end

  end
end