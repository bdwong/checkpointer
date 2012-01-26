module Checkpointer
  require 'mysql2'

  class Checkpointer
    def self.active_record_connection?
      begin
        return true if not active_record_base.connection.nil?
      rescue NameError # NameError: uninitialized constant ActiveRecord
        return false
      rescue ActiveRecord::ConnectionNotEstablished
        return false
      end
    end

    def self.active_record_base
      ActiveRecord::Base
    end

    def initialize(options={})
      @options = options.to_hash
      @connection = nil
      @checkpoint_number=0
      @last_checkpoint=0
      @db_name = options[:database] || current_database

      raise ArgumentError.new("No database name specified or no database selected.") if @db_name.nil?
      @db_backup =  options[:backup] || "#{@db_name}_backup"
    end

    def connection_options_specified?
      [:host, :database, :username, :password, :socket].any? do |option|
        not @options[option].nil?
      end
    end

    def has_required_options?
      [:database, :username].all? do |key|
        @options.has_key?(key)
      end
    end

    def sql_connection
      # escaped = client.escape("gi'thu\"bbe\0r's")
      # results = client.query("SELECT * FROM users WHERE group='#{escaped}'")
      return @connection if @connection

      if connection_options_specified? or not Checkpointer.active_record_connection?
        raise ArgumentError.new('Missing required option') unless has_required_options?
        @connection = Mysql2::Client.new(@options)
      else
        @connection = Checkpointer.active_record_base.connection.raw_connection
        if not @connection.kind_of?(Mysql2::Client)
          raise RuntimeError.new('Checkpointer only works with Mysql2 client on ActiveRecord.')
       end
      end
      @connection
    end

    def current_database
      result = sql_connection.query('SELECT DATABASE();')
      return nil if result.count==0
      result.to_a[0][0]
    end

    def tracking_table
      "updated_tables"
    end

    # Create monitoring triggers
    # Prerequisite: database is backed up.
    def track
      drop_tracking_table
      create_tracking_table
      add_triggers
      backup
    end

    # Delete monitoring triggers
    def untrack
      remove_triggers
      drop_tracking_table
    end

    # Checkpoint behavior
    # checkpoint(no name) should +1 the checkpoint number.
    # checkpoint(name) should checkpoint that name.
    # checkpoint(number) should fail with an error..
    def checkpoint(cp=nil)
      raise ArgumentError.new("Manual checkpoints cannot be a number.") if is_number?(cp)

      # Backup all changed tables.
      table_names = changed_tables_from(@db_name)
      if cp.nil?
        @checkpoint_number += 1
        cp = @checkpoint_number
      end
      db_checkpoint = "#{@db_backup}_#{cp}"
      DatabaseCopier.create_database(db_checkpoint)
      DatabaseCopier.copy_tables(table_names, @db_name, db_checkpoint)
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
      DatabaseCopier.copy_tables(changed_tables - checkpoint_tables, @db_backup, @db_name)
      
      # Restore tables from checkpoint.
      # This must come last because the tracking table must be restored last,
      # otherwise triggers will update the tracking table incorrectly.
      DatabaseCopier.copy_tables(checkpoint_tables, db_checkpoint, @db_name)

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
    # def drop(cpname=nil)
    #   if cpname.nil?
    #     checkpoints.each do |cp|
    #       if is_number?(cp) and cp.to_i >= @checkpoint_number
    #         puts "Dropping checkpoint #{cp}."
    #         sql_connection.execute("DROP DATABASE #{@db_backup}_#{cp}")
    #       end
    #     end
    #     @checkpoint_number -= 1
    #     @last_checkpoint = @checkpoint_number
    #   else
    #     if not checkpoints.include?(cpname.to_s)
    #       puts "Checkpoint #{cpname} not found."
    #       return
    #     end
    #     puts "Dropping checkpoint #{cpname}."
    #     sql_connection.execute("DROP DATABASE #{@db_backup}_#{cpname}")
    #     if @last_checkpoint == cpname
    #       @last_checkpoint = @checkpoint_number
    #     end
    #   end
    #   @last_checkpoint
    # end

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
          sql_connection.execute("DROP DATABASE #{@db_backup}_#{cp}")
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
      sql_connection.execute("DROP DATABASE #{@db_backup}_#{cpname}")
      if @last_checkpoint == cpname
        @last_checkpoint = @checkpoint_number
      end
      @last_checkpoint
    end


    # List checkpoints found by the database engine.
    def checkpoints
      result = sql_connection.execute("SHOW DATABASES LIKE '#{@db_backup.gsub("_", "\\_")}\\_%'")
      prefix_length = @db_backup.length+1
      result.to_a.flatten.map {|db| db[prefix_length..-1] }
    end

    def backup
      DatabaseCopier.copy_database(@db_name, @db_backup)
    end

    def restore_all
      tables = tables_from(@db_backup)
      DatabaseCopier.copy_tables(tables, @db_backup, @db_name)
      # Ensure tracking table
      create_tracking_table
    end

    private
    def is_number?(value)
      value.kind_of?(Fixnum) or value.to_i.to_s == value
    end

    def tables_from(db)
      result = sql_connection.select_all("SHOW TABLES FROM #{db}")
      result = result.map {|r| r.values}.flatten
      # Ensure tracking table is last, if present.
      if result.include?(tracking_table)
        result = (result-[tracking_table]) << tracking_table
      end
      result
    end

    # Select table names from tracking table
    def changed_tables_from(db)
      result = sql_connection.execute("SELECT name FROM #{db}.#{tracking_table}")
      result.to_a.flatten << tracking_table
    end

    def create_tracking_table
      sql_connection.execute("CREATE TABLE IF NOT EXISTS #{@db_name}.#{tracking_table}(name char(64), PRIMARY KEY (name));")
      #sql_connection.execute("CREATE TABLE IF NOT EXISTS #{@db_name}.#{tracking_table}(name char(64), PRIMARY KEY (name)) ENGINE = MEMORY;")
    end

    def drop_tracking_table
      sql_connection.execute("DROP TABLE IF EXISTS #{@db_name}.#{tracking_table};")
    end

    # Add triggers to all tables except tracking table
    def add_triggers
      puts "Adding triggers, this could take a while..."
      tables = tables_from(@db_name)
      tables.reject{|r| r==tracking_table}.each do |t|
        print "t"
        ["insert", "update", "delete"].each do |operation|
          cmd = <<-EOF
             CREATE TRIGGER #{@db_name}.#{t}_#{operation} AFTER #{operation} \
              ON #{t} FOR EACH ROW \
              INSERT IGNORE INTO #{@db_name}.#{tracking_table} VALUE ("#{t}");
          EOF
          begin
            sql_connection.execute(cmd)
          rescue ActiveRecord::StatementInvalid => e
            raise unless e.message =~ /multiple triggers/
            # Triggers already installed.
          end
        end
      end
      puts "Triggers added."
    end

      # Remove triggers from all tables except tracking table
    def remove_triggers
      puts "Removing triggers, this could take a while..."
      tables = tables_from(@db_name)
      tables.reject{|r| r==tracking_table}.each do |t|
        print "u"
        ["insert", "update", "delete"].each do |operation|
          cmd = "DROP TRIGGER IF EXISTS #{@db_name}.#{t}_#{operation};"
          sql_connection.execute(cmd)
        end
      end
      puts "Triggers removed."
    end

  end
end