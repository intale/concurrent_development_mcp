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
        return if head.decision_revision.zero?

        event = @event_store.read_latest(
          @stream_factory.decision(head.decision_id),
          LatestEventReadCriteria.new(
            event_types: %w[DecisionRecorded DecisionDefinitionCorrected],
            from_revision: head.decision_revision - 1
          )
        )
        event && load_event(event)
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

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
