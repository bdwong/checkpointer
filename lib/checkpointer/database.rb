require 'checkpointer/database/adapter'
require 'checkpointer/database/mysql2_adapter'
require 'checkpointer/database/active_record_adapter'

module Checkpointer
  module Database
    class DuplicateTriggerError < Exception; end
    class DatabaseNotFoundError < Exception; end

    def database_adapters
      [ActiveRecordAdapter, Mysql2Adapter]
    end

    # Get the first configured database adapter.
    def autodetect_database_adapter
      configured_adapter = database_adapters.find do |adapter|
        adapter.configured?
      end
      raise RuntimeError.new("No configured database adapters") unless configured_adapter
      configured_adapter
    end
  end
end