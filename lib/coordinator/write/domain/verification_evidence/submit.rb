# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationEvidence
      class Submit
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          outcome_digest_builder: CompatibilityAssessments::OutcomeDigestBuilder.new
        )
          @stream_factory = stream_factory
          @outcome_digest_builder = outcome_digest_builder
        end

        def call(
          state:,
          command:,
          evidence_id:,
          assessment_input_digest:,
          evidence_event:,
          submitted_at:
        )
          denial = denied(state, command, assessment_input_digest, submitted_at)
          return Failure(denial) if denial

          evidence = build_evidence(
            state:,
            command:,
            evidence_id:,
            assessment_input_digest:,
            submitted_at:
          )
          writes = [ write(command.obligation_id, evidence) ]
          evidence_reference = CompatibilityAssessments::EvidenceDecisionReferenceV1.new(
            evidence_kind: evidence.evidence_kind,
            evidence_id: evidence.evidence_id,
            conclusion: evidence.assessment.conclusion,
            result_digest: evidence.assessment.result_digest,
            assessment_input_digest: evidence.assessment_input_digest,
            event: evidence_event
          )
          terminal = terminal_event(state, evidence, evidence_reference, submitted_at)
          writes << write(command.obligation_id, terminal) if terminal

          Success(EventPlan.new(writes:))
        end

        private

        def denied(state, command, assessment_input_digest, submitted_at)
          return error(:verification_obligation_not_found, "Verification obligation does not exist", command) if state.absent?
          return terminal_error(state, command) if state.terminal?
          return error(:verification_obligation_policy_stale, "Verification obligation policy is no longer current", command) unless state.policy_current
          return error(:verification_obligation_unclaimed, "Verification obligation has no claim", command) unless state.latest_claim

          claim_denial(state, command, submitted_at) ||
            binding_denial(state, command) ||
            evidence_denial(state, command, assessment_input_digest)
        end

        def claim_denial(state, command, submitted_at)
          claim = state.latest_claim
          requested = command.claim
          unless claim.claim_id == requested.claim_id && claim.fencing_token == requested.fencing_token
            return error(
              :verification_obligation_claim_stale,
              "Verification obligation claim fence is stale",
              command,
              current_claim_id: claim.claim_id,
              current_fencing_token: claim.fencing_token
            )
          end
          unless claim.claimant_id == command.actor.id
            return error(
              :verification_obligation_claim_not_owned,
              "Verification obligation claim belongs to another agent",
              command,
              claimant_id: claim.claimant_id
            )
          end
          return if state.active_claim_at(submitted_at)

          error(
            :verification_obligation_claim_expired,
            "Verification obligation claim has expired",
            command,
            expires_at: claim.expires_at
          )
        end

        def binding_denial(state, command)
          obligation = state.obligation
          binding = command.binding
          valid = binding.obligation_validity_input_digest == obligation.validity_input_digest &&
            candidate_matches?(binding.source_candidate, obligation.source_candidate) &&
            candidate_matches?(binding.target_candidate, obligation.target_candidate)
          return if valid

          error(
            :verification_obligation_binding_stale,
            "Compatibility assessment is bound to stale candidate inputs",
            command,
            current_validity_input_digest: obligation.validity_input_digest
          )
        end

        def evidence_denial(state, command, assessment_input_digest)
          kind = command.assessment.evidence_kind
          unless state.obligation.required_evidence.include?(kind)
            return error(
              :verification_evidence_kind_not_required,
              "Evidence kind is not required by this obligation",
              command,
              evidence_kind: kind
            )
          end
          if state.duplicate_assessment?(assessment_input_digest)
            return error(
              :verification_evidence_duplicate,
              "This compatibility assessment was already accepted",
              command,
              assessment_input_digest:
            )
          end
          return unless state.evidence_limit_reached?

          error(
            :verification_evidence_limit_reached,
            "Verification obligation has reached its evidence limit",
            command,
            maximum_count: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT
          )
        end

        def candidate_matches?(binding, candidate)
          binding.candidate_id == candidate.candidate_id &&
            binding.head_commit_oid == candidate.head_commit_oid
        end

        def build_evidence(state:, command:, evidence_id:, assessment_input_digest:, submitted_at:)
          obligation = state.obligation
          claim = state.latest_claim
          Events::VerificationEvidenceSubmittedV1.new(
            obligation_id: obligation.obligation_id,
            obligation_event: state.obligation_event,
            evidence_id:,
            evidence_kind: command.assessment.evidence_kind,
            claim: {
              claim_id: claim.claim_id,
              claimant_id: claim.claimant_id,
              fencing_token: claim.fencing_token,
              claim_event: state.latest_claim_event
            },
            source_candidate: obligation.source_candidate,
            target_candidate: obligation.target_candidate,
            policy: obligation.policy,
            obligation_validity_input_digest: obligation.validity_input_digest,
            assessment: command.assessment,
            assessment_input_digest:,
            submitted_at:
          )
        end

        def terminal_event(state, evidence, evidence_reference, submitted_at)
          return failed_event(state.obligation, state.obligation_event, evidence_reference, submitted_at) if evidence.assessment.conclusion == "failed"
          return unless evidence.assessment.conclusion == "passed"

          selected = state.passed_evidence_by_kind.merge(evidence.evidence_kind => evidence_reference)
          return unless state.obligation.required_evidence.all? { selected.key?(_1) }

          selected_evidence = state.obligation.required_evidence.map { selected.fetch(_1) }
          Events::VerificationObligationSatisfiedV1.new(
            obligation_id: state.obligation.obligation_id,
            obligation_event: state.obligation_event,
            policy: state.obligation.policy,
            selected_evidence:,
            outcome_digest: @outcome_digest_builder.satisfied(
              obligation: state.obligation,
              selected_evidence:
            ),
            satisfied_at: submitted_at
          )
        end

        def failed_event(obligation, obligation_event, evidence_reference, submitted_at)
          Events::VerificationObligationFailedV1.new(
            obligation_id: obligation.obligation_id,
            obligation_event:,
            policy: obligation.policy,
            triggering_evidence: evidence_reference,
            outcome_digest: @outcome_digest_builder.failed(
              obligation:,
              triggering_evidence: evidence_reference
            ),
            failed_at: submitted_at
          )
        end

        def write(obligation_id, event)
          EventWrite.new(
            stream: @stream_factory.verification_obligation(obligation_id),
            event:
          )
        end

        def terminal_error(state, command)
          error(
            :verification_obligation_terminal,
            "Verification obligation is already terminal",
            command,
            status: state.status
          )
        end

        def error(code, message, command, details = {})
          OutcomeError.new(
            code:,
            message:,
            details: { obligation_id: command.obligation_id }.merge(details)
          )
        end
      end
    end
  end
end
