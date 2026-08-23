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
          validity_builder: Coordinator::Write::CandidateObligations::ValidityBuilder.new,
          stream_factory: StreamFactory.new
        )
          @matcher = matcher
          @validity_builder = validity_builder
          @stream_factory = stream_factory
        end

        def call(state:, command:, created_at:)
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
            reasons:,
            created_at: state.existing&.created_at || created_at
          )
          return replay(state.existing, obligation) if state.existing

          plan = EventPlan.new(
            writes: [
              EventWrite.new(
                stream: @stream_factory.verification_obligation(command.obligation_id),
                event: obligation
              )
            ]
          )
          Success(Coordinator::Write::CandidateObligations::DecisionV1.created(plan, obligation))
        end

        private

        def build_obligation(state:, command:, policy:, reasons:, created_at:)
          validity = @validity_builder.call(
            source: state.source,
            target: state.target,
            reasons:,
            policy:,
            rule_version: command.rule_version
          )
          Events::VerificationObligationCreatedV1.new(
            obligation_id: command.obligation_id,
            kind: "candidate_compatibility",
            status: "open",
            change_set_id: state.source.subject.change_set_id,
            source_candidate: state.source.subject,
            target_candidate: state.target.subject,
            reasons:,
            required_evidence: policy.required_evidence,
            enforcement: policy.enforcement,
            policy:,
            validity_input_digest: validity.digest,
            rule_version: command.rule_version,
            created_at:
          )
        end

        def replay(existing, expected)
          unless existing == expected
            invalid!(
              "obligation_replay_mismatch",
              obligation_id: expected.obligation_id,
              existing_validity_input_digest: existing.validity_input_digest,
              expected_validity_input_digest: expected.validity_input_digest
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
