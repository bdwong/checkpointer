module Checkpointer
  module Database
  	class Adapter
      def self.configured?
        false
      end

      def initialize(options={})
      end

      def current_database
      end

      def connection
      end

      def close_connection
      end

      def execute(query)
      end

      def escape(value)
      end

      #TODO
      # def connection_options_specified?
      #   [:host, :database, :username, :password, :socket].any? do |option|
      #     not @options[option].nil?
      #   end
      # end

      # def has_required_options?
      #   [:database, :username].all? do |key|
      #     @options.has_key?(key)
      #   end
      # end

  	end
  end
end