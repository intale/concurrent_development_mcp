# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class DecisionDefinitionLoader
      def initialize(
        event_store:,
        exact_loader: ExactEventLoader.new(event_store:),
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @canonical_json = canonical_json
      end

      def call(head:, partition:)
        validate_head_reference!(head)
        persisted = @exact_loader.call(head.event)

        case persisted.payload
        when Events::DecisionActivatedV1
          definition_from_activation(head, persisted.payload, partition)
        when Events::DecisionDefinitionCorrectedV1
          definition_from_correction(head, persisted.payload, partition)
        when Events::DecisionActivatedV2
          definition_from_cohesive_activation(head, persisted.payload)
        when Events::DecisionDefinitionCorrectedV2
          definition_from_cohesive_correction(head, persisted.payload)
        else
          invalid!("candidate_impact_policy_head_type_invalid", decision_head: head.to_h)
        end
      end

      private

      def validate_head_reference!(head)
        reference = head.event
        valid = head.decision_revision == reference.stream_revision &&
                reference.stream_context == "HumanGuidance" &&
                reference.stream_name == "Decision" &&
                reference.stream_id == head.decision_id &&
                %w[DecisionActivated DecisionDefinitionCorrected].include?(reference.type)
        return if valid

        invalid!("candidate_impact_policy_head_invalid", decision_head: head.to_h)
      end

      def definition_from_activation(head, activation, partition)
        recorded = @exact_loader.call(activation.recorded_event)
        definition_event = payload!(recorded, Events::DecisionRecordedV1)
        valid = activation.decision_id == head.decision_id &&
                activation.partitions.include?(partition) &&
                definition_event.decision_id == head.decision_id &&
                definition_event.definition.digest == activation.definition_digest &&
                recorded.reference.stream_context == "HumanGuidance" &&
                recorded.reference.stream_name == "Decision" &&
                recorded.reference.stream_id == head.decision_id
        return definition_event.definition if valid

        invalid!("candidate_impact_policy_activation_invalid", decision_head: head.to_h)
      end

      def definition_from_correction(head, correction, partition)
        valid = correction.decision_id == head.decision_id &&
                correction.previous_head.decision_id == head.decision_id &&
                correction.previous_head.decision_revision < head.decision_revision &&
                correction.partitions.include?(partition)
        return correction.definition if valid

        invalid!("candidate_impact_policy_correction_invalid", decision_head: head.to_h)
      end

      def definition_from_cohesive_activation(head, activation)
        definition_event = cohesive_definition_event(head)
        valid = activation.decision_id == head.decision_id &&
                definition_event &&
                definition_event.decision_id == head.decision_id &&
                definition_event.interpretation_id == activation.interpretation_id
        return wrap_definition(definition_event.definition) if valid

        invalid!("candidate_impact_policy_activation_invalid", decision_head: head.to_h)
      end

      def definition_from_cohesive_correction(head, correction)
        return wrap_definition(correction.definition) if correction.decision_id == head.decision_id

        invalid!("candidate_impact_policy_correction_invalid", decision_head: head.to_h)
      end

      def cohesive_definition_event(head)
        @event_store.read_grouped(
          @stream_factory.decision(head.decision_id),
          EventQueries::DECISION_CORRECTION_STATE
        ).select { _1.stream_revision < head.decision_revision }
          .map { load_event(_1) }
          .find { _1.is_a?(Events::DecisionRecordedV2) || _1.is_a?(Events::DecisionDefinitionCorrectedV2) }
      end

      def wrap_definition(document)
        Decisions::DecisionDefinitionV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h)
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def payload!(persisted, expected_class)
        return persisted.payload if persisted.payload.is_a?(expected_class)

        invalid!(
          "referenced_event_type_invalid",
          reference: persisted.reference.to_h,
          expected_class: expected_class.name,
          actual_class: persisted.payload.class.name
        )
      end

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
