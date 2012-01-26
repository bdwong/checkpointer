require 'checkpointer/database/adapter'
require 'checkpointer/database/mysql2_adapter'
require 'checkpointer/database/active_record_adapter'

module Checkpointer
  module Database
  	def autodetect_database_adapter
  	end
  end
end