require 'checkpointer/version'
require 'checkpointer/database'
require 'checkpointer/database_copier'
require 'checkpointer/database/tracker'

module Checkpointer
  require 'mysql2'

  class Checkpointer
    include ::Checkpointer::Database

    def initialize(options={})
      @options = options.to_hash
      extract_options(@options)
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

    # Deletes recognized checkpointer options keys from the options hash
    # and stores them in @cp_options
    def extract_options(options)
      @cp_options = {}
      [:tables].each do |key|
        value = options.delete(key)
        @cp_options[key] = value unless value.nil?
      end
    end

    # filter list of tables according to table_opts options.
    def filtered_tables(tables, table_opts=nil)
      table_opts ||= @cp_options[:tables]

      # Understands the following forms:
      # nil
      # :tables => :all
      # :tables => ['table1', 'table2', 'table3']
      # :tables => {:only => ['table1']}
      # :tables => {:only => 'table1'}
      # :tables => {:except => ['table2', 'table3']}
      case table_opts
      when nil, :all
        tables
      when Array
        table_opts & tables
      when Hash
        only = table_opts[:only]
        only = [only].flatten unless only.nil?
        except = table_opts[:except]
        except = [except].flatten unless except.nil?
        filtered = (only & tables) || tables.clone
        filtered -= except || []
      else
        raise ArgumentError.new("Invalid :tables option '#{table_opts}'")
      end
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
      table_names = @tracker.changed_tables_from(@db_name) << @tracker.tracking_table
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
    def restore(cp=@last_checkpoint, table_opts=nil)
      checkpoint_tables=[]
      if cp != 0
        db_checkpoint = "#{@db_backup}_#{cp}"
        checkpoint_tables = @tracker.tables_from(db_checkpoint)
      end

      # Get all changed tables.
      changed_tables = @tracker.changed_tables_from(@db_name)
      # puts "checkpoint tables: #{checkpoint_tables.inspect}"
      # puts "changed tables: #{changed_tables.inspect}"
      # puts "difference: #{(changed_tables - checkpoint_tables).inspect}"

      # Restore tables not in the checkpoint from backup
      db_copier = DatabaseCopier.from_connection(@db_adapter)
      base_updates = filtered_tables(changed_tables - checkpoint_tables, table_opts)
      db_copier.copy_tables(base_updates, @db_backup, @db_name) do |tbl, op|
        @tracker.add_triggers_to_table(@db_name, tbl) if [:drop_and_create, :create].include?(op)
      end
      
      # Restore tables from checkpoint.
      # This must come last because the tracking table must be restored last,
      # otherwise triggers will update the tracking table incorrectly.
      checkpoint_updates = filtered_tables(checkpoint_tables, table_opts)
      db_copier.copy_tables(checkpoint_updates, db_checkpoint, @db_name) do |tbl, op|
        @tracker.add_triggers_to_table(@db_name, tbl) if [:drop_and_create, :create].include?(op)
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
      tables = @tracker.tables_from(@db_backup)
      db_copier = DatabaseCopier.from_connection(@db_adapter)
      db_copier.drop_tables_not_in_source(@db_backup, @db_name)
      db_copier.copy_tables(tables, @db_backup, @db_name) do |tbl, op|
        @tracker.add_triggers_to_table(@db_name, tbl) if [:drop_and_create, :create].include?(op)
      end
      # Ensure tracking table
      @tracker.create_tracking_table
    end

    private
    def is_number?(value)
      value.kind_of?(Fixnum) or (value.respond_to?(:to_i) and value.to_i.to_s == value)
    end
  end
end