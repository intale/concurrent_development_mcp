# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationTargetStoreSelectedV1 < Base
      contract type: "HistoryMigrationTargetStoreSelected", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :target_config_name, Types::Identifier
    end
  end
end
