# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationSourceStoreSelectedV1 < Base
      contract type: "HistoryMigrationSourceStoreSelected", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :source_config_name, Types::Identifier
    end
  end
end
