# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationEvidence
      class State < Value
        Observation = Types.Instance(CompatibilityAssessments::EvidenceObservationV1)

        attribute :obligation, Types.Instance(Events::VerificationObligationCreatedV1).optional
        attribute :obligation_event, Types.Instance(EventReference).optional
        attribute :latest_claim, Types.Instance(Events::VerificationObligationClaimedV1).optional
        attribute :latest_claim_event, Types.Instance(EventReference).optional
        attribute :evidence, Types::Array.of(Observation).constrained(
          max_size: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT
        )
        attribute :satisfied, Types.Instance(Events::VerificationObligationSatisfiedV1).optional
        attribute :failed, Types.Instance(Events::VerificationObligationFailedV1).optional
        attribute? :waived, Types.Instance(Events::VerificationObligationWaivedV1).optional
        attribute? :invalidated, Types.Instance(Events::VerificationObligationInvalidatedV1).optional
        attribute :policy_current, Types::Bool

        def self.initial
          new(
            obligation: nil,
            obligation_event: nil,
            latest_claim: nil,
            latest_claim_event: nil,
            evidence: [],
            satisfied: nil,
            failed: nil,
            waived: nil,
            invalidated: nil,
            policy_current: false
          )
        end

        def absent?
          obligation.nil?
        end

        def terminal?
          !satisfied.nil? || !failed.nil? || !waived.nil? || !invalidated.nil?
        end

        def status
          return "invalidated" if invalidated
          return "waived" if waived
          return "satisfied" if satisfied
          return "failed" if failed

          "open"
        end

        def active_claim_at(timestamp)
          return unless latest_claim&.expires_at&.>(timestamp)

          latest_claim
        end

        def duplicate_assessment?(assessment_input_digest)
          evidence.any? { _1.evidence.assessment_input_digest == assessment_input_digest }
        end

        def evidence_limit_reached?
          evidence.length >= Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT
        end

        def passed_evidence_by_kind
          evidence.each_with_object({}) do |observation, selected|
            reference = observation.decision_reference
            selected[reference.evidence_kind] = reference if reference.conclusion == "passed"
          end.freeze
        end
      end
    end
  end
end
