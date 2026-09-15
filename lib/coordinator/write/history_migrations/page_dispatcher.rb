# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageDispatcher
      include Dry::Monads[:result]

      def initialize(source_loader:, event_dispatcher:)
        @source_loader = source_loader
        @event_dispatcher = event_dispatcher
      end

      def call(migration:, page:)
        count = 0
        @source_loader.call(page).each do |source_event|
          result = @event_dispatcher.call(
            migration_id: migration.migration_id,
            source_config_name: migration.source_config_name,
            source_upper_position: migration.source_upper_position,
            source_event:
          )
          return result if result.failure?

          count += result.value!.events.length
        end
        Success(count)
      end
    end
  end
end
