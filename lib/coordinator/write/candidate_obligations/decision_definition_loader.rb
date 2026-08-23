# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class DecisionDefinitionLoader
      def initialize(event_store:, exact_loader: ExactEventLoader.new(event_store:))
        @exact_loader = exact_loader
      end

      def call(head:, partition:)
        validate_head_reference!(head)
        persisted = @exact_loader.call(head.event)

        case persisted.payload
        when Events::DecisionActivatedV1
          definition_from_activation(head, persisted.payload, partition)
        when Events::DecisionDefinitionCorrectedV1
          definition_from_correction(head, persisted.payload, partition)
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
