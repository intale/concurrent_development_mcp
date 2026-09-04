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
        when Events::DecisionActivatedV1
          activated_state(head, payload)
        when Events::DecisionDefinitionCorrectedV1
          corrected_state(head, payload)
        when Events::DecisionActivatedV2
          cohesive_activated_state(head, payload)
        when Events::DecisionDefinitionCorrectedV2
          cohesive_corrected_state(head, payload)
        else
          invalid!("historical_decision_head_type_invalid", decision_head: head.to_h)
        end
      end

      private

      def activated_state(head, activation)
        recorded_event = read_reference(activation.recorded_event)
        unless recorded_event
          invalid!("historical_decision_definition_missing", decision_head: head.to_h)
        end
        recorded = load(recorded_event)
        valid = recorded.is_a?(Events::DecisionRecordedV1) &&
                recorded.decision_id == head.decision_id &&
                activation.decision_id == head.decision_id &&
                activation.definition_digest == recorded.definition.digest
        invalid!("historical_decision_activation_invalid", decision_head: head.to_h) unless valid

        Decisions::DecisionCurrentStateV1.new(
          decision_id: head.decision_id,
          definition: recorded.definition,
          head:,
          slot: activation.slot,
          partitions: activation.partitions
        )
      end

      def corrected_state(head, correction)
        valid = correction.decision_id == head.decision_id &&
                correction.previous_head.decision_id == head.decision_id &&
                correction.previous_head.decision_revision < head.decision_revision
        invalid!("historical_decision_correction_invalid", decision_head: head.to_h) unless valid

        Decisions::DecisionCurrentStateV1.new(
          decision_id: head.decision_id,
          definition: correction.definition,
          head:,
          slot: correction.slot,
          partitions: correction.partitions
        )
      end

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

      def read_reference(reference)
        event = @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        event if event && self.reference(event) == reference
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
