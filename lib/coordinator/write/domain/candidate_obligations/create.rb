# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligations
      class Create
        include Dry::Monads[:result]

        POLICY_OUTCOMES = {
          "stale" => "stale_policy",
          "non_gating" => "non_gating_policy",
          "inactive" => "inactive_policy"
        }.freeze

        def initialize(
          matcher: Coordinator::Write::CandidateObligations::Matcher.new,
          stream_factory: StreamFactory.new
        )
          @matcher = matcher
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          policy_outcome = POLICY_OUTCOMES[state.policy.status]
          return Success(Coordinator::Write::CandidateObligations::DecisionV1.no_event(policy_outcome)) if policy_outcome

          policy = state.policy.evidence
          invalid!("gating_policy_evidence_missing", obligation_id: command.obligation_id) unless policy
          reasons = @matcher.call(source: state.source, target: state.target)
          if reasons.empty?
            invalid!("existing_obligation_has_no_directional_match", obligation_id: command.obligation_id) if state.existing
            return Success(Coordinator::Write::CandidateObligations::DecisionV1.no_event("no_match"))
          end

          obligation = build_obligation(
            state:,
            command:,
            policy:,
            reasons:
          )
          return replay(state.existing, obligation) if state.existing

          stream = @stream_factory.verification_obligation(command.obligation_id)
          plan = EventPlan.new(writes: [
            EventWrite.new(stream:, event: obligation),
            EventWrite.new(
              stream:,
              event: Events::VerificationObligationAddedToChangeSetV1.new(
                obligation_id: command.obligation_id,
                change_set_id: state.source.subject.change_set_id
              )
            ),
            EventWrite.new(
              stream:,
              event: Events::VerificationObligationSourceCandidateAssignedV1.new(
                obligation_id: command.obligation_id,
                candidate_id: state.source.subject.candidate_id
              )
            ),
            EventWrite.new(
              stream:,
              event: Events::VerificationObligationTargetCandidateAssignedV1.new(
                obligation_id: command.obligation_id,
                candidate_id: state.target.subject.candidate_id
              )
            )
          ])
          Success(Coordinator::Write::CandidateObligations::DecisionV1.created(plan, obligation))
        end

        private

        def build_obligation(state:, command:, policy:, reasons:)
          Events::VerificationObligationCreatedV2.new(
            obligation_id: command.obligation_id,
            kind: "candidate_compatibility",
            reasons: reasons.map(&:kind),
            required_evidence: policy.required_evidence,
            enforcement: policy.enforcement
          )
        end

        def replay(existing, expected)
          unless existing.obligation_id == expected.obligation_id &&
                 existing.kind == expected.kind &&
                 existing.enforcement == expected.enforcement &&
                 existing.reasons.map(&:kind) == expected.reasons &&
                 existing.required_evidence == expected.required_evidence
            invalid!(
              "obligation_replay_mismatch",
              obligation_id: expected.obligation_id,
              existing_validity_input_digest: existing.validity_input_digest
            )
          end

          Success(Coordinator::Write::CandidateObligations::DecisionV1.replayed(existing))
        end

        def invalid!(reason, evidence)
          raise Coordinator::Write::CandidateObligations::InvalidHistory.new(reason:, evidence:)
        end
      end
    end
  end
end
