# frozen_string_literal: true

module Coordinator
  class CommandCompletionLookup
    def initialize(
      receipts: Repositories::CommandReceipts.new,
      event_store: Container["event_store"],
      stream_factory: StreamFactory.new,
      schema_registry: EventSchemaRegistry.new
    )
      @receipts = receipts
      @event_store = event_store
      @stream_factory = stream_factory
      @schema_registry = schema_registry
    end

    def fetch(command_id)
      @receipts.fetch(command_id) || fetch_authoritative(command_id)
    end

    private

    def fetch_authoritative(command_id)
      event = @event_store.read(
        @stream_factory.command(command_id),
        EventQueries::COMMAND_COMPLETION
      ).first
      return unless event

      @schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
    end
  end
end
