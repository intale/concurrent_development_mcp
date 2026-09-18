# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PagePlanningDispatcher
      include Dry::Monads[:result]

      def initialize(event_store:, source_loader:, event_planning_dispatcher:)
        @event_store = event_store
        @source_loader = source_loader
        @event_planning_dispatcher = event_planning_dispatcher
      end

      def call(migration:, page:)
        count = 0
        @source_loader.call(page).each do |source_event|
          result = @event_store.multiple do
            @event_planning_dispatcher.call(
              migration_id: migration.migration_id,
              source_config_name: migration.source_config_name,
              source_upper_position: migration.source_upper_position,
              source_event:
            )
          end
          return result if result.failure?

          count += result.value!.length
        end
        Success(count)
      end
    end
  end
end
