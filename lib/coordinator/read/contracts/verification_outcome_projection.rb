# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class VerificationOutcomeProjection < Dry::Validation::Contract
      Outcome = Types.Instance(Coordinator::Write::Events::VerificationObligationSatisfiedV1) |
        Types.Instance(Coordinator::Write::Events::VerificationObligationFailedV1)

      params do
        required(:obligation).value(Types.Instance(Coordinator::Write::Events::VerificationObligationCreatedV1))
        required(:obligation_event).value(Types.Instance(Coordinator::Write::EventReference))
        required(:evidence).value(
          Types::Array.of(Types.Instance(VerificationEvidenceProjectionObservationV1))
            .constrained(max_size: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT)
        )
        required(:outcome).value(Outcome)
        required(:outcome_event).value(Types.Instance(Coordinator::Write::EventReference))
        required(:current_status).filled(:string, eql?: "open")
      end

      rule do
        key(:outcome).failure("must match exact projected evidence and obligation") unless coherent?(values)
      end

      private

      def coherent?(values)
        obligation = values[:obligation]
        outcome = values[:outcome]
        outcome_event = values[:outcome_event]
        evidence = values[:evidence]
        common = outcome.obligation_id == obligation.obligation_id &&
          outcome.obligation_event == values[:obligation_event] &&
          outcome.policy == obligation.policy &&
          same_stream?(outcome_event, obligation.obligation_id) &&
          later_than_evidence?(outcome_event, evidence)
        return false unless common

        case outcome
        when Coordinator::Write::Events::VerificationObligationSatisfiedV1
          coherent_satisfaction?(outcome, obligation, evidence, outcome_event)
        when Coordinator::Write::Events::VerificationObligationFailedV1
          coherent_failure?(outcome, evidence, outcome_event)
        else
          false
        end
      end

      def coherent_satisfaction?(outcome, obligation, evidence, outcome_event)
        references = evidence.map { decision_reference(_1) }
        outcome_event.type == "VerificationObligationSatisfied" &&
          outcome.selected_evidence.map(&:evidence_kind) == obligation.required_evidence &&
          outcome.selected_evidence.all? { _1.conclusion == "passed" && references.include?(_1) }
      end

      def coherent_failure?(outcome, evidence, outcome_event)
        outcome_event.type == "VerificationObligationFailed" &&
          outcome.triggering_evidence.conclusion == "failed" &&
          evidence.map { decision_reference(_1) }.include?(outcome.triggering_evidence)
      end

      def later_than_evidence?(outcome_event, evidence)
        latest = evidence.map { _1.event.stream_revision }.max
        latest && outcome_event.stream_revision > latest
      end

      def decision_reference(observation)
        submission = observation.submission
        Coordinator::Write::CompatibilityAssessments::EvidenceDecisionReferenceV1.new(
          evidence_kind: submission.evidence_kind,
          evidence_id: submission.evidence_id,
          conclusion: submission.assessment.conclusion,
          result_digest: submission.assessment.result_digest,
          assessment_input_digest: submission.assessment_input_digest,
          event: observation.event
        )
      end

      def same_stream?(reference, obligation_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == obligation_id
      end
    end
  end
end
