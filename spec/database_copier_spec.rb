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
        mock_adapter = double(:new => @connection)
        DatabaseCopier.any_instance.stub(:autodetect_database_adapter).and_return(mock_adapter)
        @d = DatabaseCopier.new
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
      end
    end

  end
end