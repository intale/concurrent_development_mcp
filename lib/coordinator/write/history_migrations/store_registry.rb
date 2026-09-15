# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class StoreRegistry
      SOURCE_CONFIG_NAME = "default"
      TARGET_CONFIG_NAME = "migration_target"

      def available?(config_name)
        PgEventstore.available_configs.include?(config_name.to_sym)
      end

      def client(config_name)
        PgEventstore.client(config_name.to_sym)
      end
    end
  end
end
