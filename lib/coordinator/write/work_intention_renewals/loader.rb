# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class Loader
      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(renewal_id)
        events = @event_store.read(@stream_factory.work_intention_set_renewal(renewal_id), EventQueries::WORK_INTENTION_RENEWAL_HISTORY)
        payloads = events.map { @schema_registry.load(type: _1.type, schema_version: _1.metadata.fetch("schema_version"), data: _1.data) }
        unless payloads.all? { _1.renewal_id == renewal_id }
          raise InvalidCommandHistory, "Renewal facts do not match their stream identity"
        end
        Snapshot.new(state: State.reduce(payloads), events:)
      end
    end
  end
end
