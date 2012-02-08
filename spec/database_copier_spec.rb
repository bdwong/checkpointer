require File.dirname(__FILE__) + '/spec_helper.rb'

module Checkpointer
  describe DatabaseCopier do
    context "instantiation" do
      it "should create instantiate a database adapter as the connection" do
        adapter_instance = double("adapter_instance")
        mock_adapter = double(:new => adapter_instance)
        DatabaseCopier.any_instance.stub(:autodetect_database_adapter).and_return(mock_adapter)

        d = DatabaseCopier.new
        d.sql_connection.should == adapter_instance
      end
    end

    context "instantiated" do
      before(:each) do
        @connection = double("adapter_instance")
        @connection.stub(:escape) {|value| value}
        @connection.stub(:identifier) {|value| "`#{value}`"}
        @connection.stub(:literal) {|value| "'#{value}'"}
        @connection.stub(:normalize_result) {|value| value}

        mock_adapter = double(:new => @connection)
        DatabaseCopier.any_instance.stub(:autodetect_database_adapter).and_return(mock_adapter)
        @d = DatabaseCopier.new
      end

      describe :create_database do
        it "should drop then create the database" do
          @connection.should_receive(:execute).with('DROP DATABASE IF EXISTS `database`')
          @connection.should_receive(:execute).with('CREATE DATABASE IF NOT EXISTS `database` CHARACTER SET utf8 COLLATE utf8_general_ci')
          @d.create_database('database')
        end
      end

      describe :create_database_for_copy do
        it "should create the target database if necessary and drop tables not in source" do
          @connection.should_receive(:execute).with('CREATE DATABASE IF NOT EXISTS `target` CHARACTER SET utf8 COLLATE utf8_general_ci')
          @connection.should_receive(:tables_from).with('source').
            and_return(['my_table'])
          @connection.should_receive(:tables_from).with('target').
            and_return(['other_table'])
          @connection.should_receive(:execute).
            with('DROP TABLE `target`.`other_table`')

          @d.create_database_for_copy('source', 'target')
        end
      end

      describe :drop_tables_not_in_source do
        it "should drop table_3 from target" do
          @connection.should_receive(:tables_from).with('source').
            and_return(['table_1', 'table_2'])
          @connection.should_receive(:tables_from).with('target').
            and_return(['table_1', 'table_2', 'table_3'])
          @connection.should_receive(:execute).
            with('DROP TABLE `target`.`table_3`')
          @d.drop_tables_not_in_source('source', 'target')
        end
      end

      describe :copy_database do
        pending
      end

      describe :show_create_table_without_increment do
        it "should remove auto_increment" do
          @connection.stub(:show_create_table).and_return(
          <<-ENDSQL
            CREATE TABLE `users` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `email` varchar(100) NOT NULL DEFAULT '',
            `created_at` datetime DEFAULT NULL,
            `updated_at` datetime DEFAULT NULL,
            `name` varchar(50) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            KEY `index_users_on_email` (`email`)
            ) ENGINE=InnoDB AUTO_INCREMENT=31 DEFAULT CHARSET=utf8
          ENDSQL
          )
          result, auto_increment = @d.show_create_table_without_increment('db', 'table')
          auto_increment.should == "31"
          result.should ==
          <<-ENDSQL
            CREATE TABLE `users` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `email` varchar(100) NOT NULL DEFAULT '',
            `created_at` datetime DEFAULT NULL,
            `updated_at` datetime DEFAULT NULL,
            `name` varchar(50) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            KEY `index_users_on_email` (`email`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8
          ENDSQL
        end

        # Test case one auto_increment string has more spaces than the other should return the same string.
        it "should remove extra spaces around auto_increment" do
          @connection.stub(:show_create_table).and_return(
          <<-ENDSQL
            CREATE TABLE `users` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `email` varchar(100) NOT NULL DEFAULT '',
            `created_at` datetime DEFAULT NULL,
            `updated_at` datetime DEFAULT NULL,
            `name` varchar(50) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            KEY `index_users_on_email` (`email`)
            ) ENGINE=InnoDB   AUTO_INCREMENT=31   DEFAULT CHARSET=utf8
          ENDSQL
          )
          result, auto_increment = @d.show_create_table_without_increment('db', 'table')
          auto_increment.should == "31"
          result.should ==
          <<-ENDSQL
            CREATE TABLE `users` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `email` varchar(100) NOT NULL DEFAULT '',
            `created_at` datetime DEFAULT NULL,
            `updated_at` datetime DEFAULT NULL,
            `name` varchar(50) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            KEY `index_users_on_email` (`email`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8
          ENDSQL
        end

        it "should return unchanged query if AUTO_INCREMENT not found" do
          create_sql = <<-ENDSQL
            CREATE TABLE `users` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `email` varchar(100) NOT NULL DEFAULT '',
            `created_at` datetime DEFAULT NULL,
            `updated_at` datetime DEFAULT NULL,
            `name` varchar(50) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            KEY `index_users_on_email` (`email`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8
          ENDSQL

          @connection.stub(:show_create_table).and_return(create_sql)
          result, auto_increment = @d.show_create_table_without_increment('db', 'table')
          auto_increment.should == 0
          result.should == create_sql
        end

        it "should return nil if table not found" do
          @connection.stub(:show_create_table).and_return(nil)
          @d.show_create_table_without_increment('db', 'table').should be_nil
        end
      end

      describe :copy_tables do
        context "no tables" do
          it "should copy nothing if no tables given" do
            @connection.should_not_receive(:execute)
            @d.copy_tables([], "source", "target").should be_nil
          end
        end

        context "with tables" do
          before(:each) do
            @connection.stub(:execute).with('set autocommit = 0;')
            @connection.stub(:execute).with('set unique_checks = 0;')
            @connection.stub(:execute).with('set foreign_key_checks = 0;')

            @connection.stub(:show_create_table) do |db, table|
              "CREATE TABLE #{table}...;"
            end
            # @connection.unstub(:show_create_table)
            # @connection.should_receive(:show_create_table).with("source", "table_1").
            #   and_return('CREATE_TABLE `table_1`...;')
            # @connection.should_receive(:show_create_table).with("target", "table_1").
            #   and_return('CREATE_TABLE `table_1`...;')
            # @connection.should_receive(:show_create_table).with("source", "table_2").
            #   and_return('CREATE_TABLE `table_2`...;')
            # @connection.should_receive(:show_create_table).with("target", "table_2").
            #   and_return('CREATE_TABLE `table_2`...;')

            @connection.stub(:execute).with('COMMIT;')
            @connection.stub(:execute).with('set foreign_key_checks = 1;')
            @connection.stub(:execute).with('set unique_checks = 1;')
            @connection.stub(:execute).with('set autocommit = 1;')
          end

          it "should copy a list of tables" do
            @connection.should_receive(:execute).with('TRUNCATE TABLE `target`.`table_1`')
            @connection.should_receive(:execute).with('INSERT INTO `target`.`table_1` SELECT * FROM `source`.`table_1`')
            @connection.should_receive(:execute).with('TRUNCATE TABLE `target`.`table_2`')
            @connection.should_receive(:execute).with('INSERT INTO `target`.`table_2` SELECT * FROM `source`.`table_2`')

            @d.copy_tables(["table_1", "table_2"], "source", "target")
          end

          context "callbacks" do
            it "should yield :truncate after truncating table" do
              @connection.unstub(:show_create_table)
              @connection.should_receive(:show_create_table).with("source", "table_1").
                and_return('CREATE_TABLE `table_1`...;')
              @connection.should_receive(:show_create_table).with("target", "table_1").
                and_return('CREATE_TABLE `table_1`...;')
              
              @connection.should_receive(:execute).with('TRUNCATE TABLE `target`.`table_1`')
              @connection.should_receive(:execute).with('INSERT INTO `target`.`table_1` SELECT * FROM `source`.`table_1`')

              yielded = false
              @d.copy_tables(["table_1"], "source", "target") do |tbl, op|
                op.should == :truncate
                tbl.should == 'table_1'
                yielded = true
              end
              yielded.should be_true
            end

            it "should yield :create after creating table" do
              @connection.unstub(:show_create_table)
              @connection.should_receive(:show_create_table).with("source", "table_1").
                and_return('CREATE_TABLE `table_1`...;')
              @connection.should_receive(:show_create_table).with("target", "table_1").
                and_return(nil)

              @connection.should_receive(:execute).with('CREATE TABLE IF NOT EXISTS `target`.`table_1` LIKE `source`.`table_1`')
              @connection.should_receive(:execute).with('INSERT INTO `target`.`table_1` SELECT * FROM `source`.`table_1`')

              yielded = false
              @d.copy_tables(["table_1"], "source", "target") do |tbl, op|
                op.should == :create
                tbl.should == 'table_1'
                yielded = true
              end
              yielded.should be_true
            end

            it "should yield :drop_and_create after dropping and recreating table" do
              @connection.unstub(:show_create_table)
              @connection.should_receive(:show_create_table).with("source", "table_1").
                and_return('CREATE_TABLE `table_1` with parameters...;')
              @connection.should_receive(:show_create_table).with("target", "table_1").
                and_return('CREATE_TABLE `table_1` with different parameters...;')

              @connection.should_receive(:execute).with('CREATE TABLE IF NOT EXISTS `target`.`table_1` LIKE `source`.`table_1`')
              @connection.should_receive(:execute).with('DROP TABLE `target`.`table_1`')
              @connection.should_receive(:execute).with('INSERT INTO `target`.`table_1` SELECT * FROM `source`.`table_1`')

              yielded = false
              @d.copy_tables(["table_1"], "source", "target") do |tbl, op|
                op.should == :drop_and_create
                tbl.should == 'table_1'
                yielded = true
              end
              yielded.should be_true
            end
          end
        end
      end
    end
  end
end