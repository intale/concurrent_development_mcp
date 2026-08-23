# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class PartitionSnapshotLoader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        reference_builder: EventReferenceBuilder.new,
        contract: Contracts::AgentChoiceImpactPartitionSnapshot.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @reference_builder = reference_builder
        @contract = contract
      end

      def call(partition)
        event = @event_store.read_grouped(
          @stream_factory.decision_partition(partition.partition_id),
          Coordinator::Write::EventQueries::DECISION_PARTITION_LATEST
        ).first
        return empty_observation(partition) unless event

        payload = load(event)
        observation = Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition:,
          partition_revision: event.stream_revision,
          event: @reference_builder.call(event),
          active_decisions: payload.active_decisions
        )
        verify!(partition, event, payload, observation)
        observation
      rescue Dry::Struct::Error,
             Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise AgentChoiceImpactProcessRejected, error.message
      end

      private

      def empty_observation(partition)
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition:,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify!(partition, event, payload, observation)
        result = @contract.call(partition:, event:, payload:, observation:)
        return if result.success?

        raise AgentChoiceImpactProcessRejected,
              "DecisionPartition repair snapshot is invalid: #{result.errors.to_h.inspect}"
      end
    end
  end
end
