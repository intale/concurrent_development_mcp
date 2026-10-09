# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class HistoricalDecisionLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        partition_builder: Decisions::DecisionPartitionBuilder.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @partition_builder = partition_builder
        @canonical_json = canonical_json
      end

      def call(head)
        event = @event_store.read_at(
          @stream_factory.decision(head.decision_id),
          head.decision_revision
        )
        unless event && reference(event) == head.event && event.stream_revision == head.decision_revision
          invalid!("historical_decision_head_missing", decision_head: head.to_h)
        end

        payload = load(event)
        case payload
        when Events::DecisionActivatedV2
          cohesive_activated_state(head, payload)
        when Events::DecisionDefinitionCorrectedV2
          cohesive_corrected_state(head, payload)
        else
          invalid!("historical_decision_head_type_invalid", decision_head: head.to_h)
        end
      end

      private

      def cohesive_activated_state(head, activation)
        recorded_event = @event_store.read_at(@stream_factory.decision(head.decision_id), 0)
        recorded = recorded_event && load(recorded_event)
        unless recorded.is_a?(Events::DecisionRecordedV2) &&
               recorded.decision_id == head.decision_id &&
               activation.decision_id == head.decision_id &&
               activation.interpretation_id == recorded.interpretation_id
          invalid!("historical_decision_activation_invalid", decision_head: head.to_h)
        end

        cohesive_state(head, recorded.definition)
      end

      def cohesive_corrected_state(head, correction)
        unless correction.decision_id == head.decision_id
          invalid!("historical_decision_correction_invalid", decision_head: head.to_h)
        end

        cohesive_state(head, correction.definition)
      end

      def cohesive_state(head, document)
        definition = Decisions::DecisionDefinitionV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h)
        )
        Decisions::DecisionCurrentStateV1.new(
          decision_id: head.decision_id,
          definition:,
          head:,
          slot: nil,
          partitions: @partition_builder.call(definition)
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
