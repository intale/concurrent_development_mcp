# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class CommandReceiptsV2
      PROJECTION = ProjectionDefinition.new(name: "command_receipts", version: 2)

      def initialize(
        source_loader:,
        assembler:,
        receipts: Repositories::CommandReceipts.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @source_loader = source_loader
        @assembler = assembler
        @receipts = receipts
        @processed_events = processed_events
      end

      def call(event)
        source = @source_loader.call(event)
        return unless source

        result = @assembler.call(source)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: event.created_at
          )

          @receipts.store(event:, result:)
        end

        nil
      end
    end
  end
end
