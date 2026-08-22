# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class CommandReceiptsV1
      PROJECTION = ProjectionDefinition.new(name: "command_receipts", version: 1)

      def initialize(
        contract: Contracts::CommandReceiptSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        receipts: Repositories::CommandReceipts.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @receipts = receipts
        @processed_events = processed_events
      end

      def call(event)
        completion = load_completion(event)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: Time.now.utc
          )

          @receipts.store(event:, completion:)
        end

        nil
      end

      private

      def load_completion(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
