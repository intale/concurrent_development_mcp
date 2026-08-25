# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class ToolResultMapper
      STATUS_BY_CODE = {
        command_id_reused: "command_id_reused",
        work_item_unavailable: "conflict",
        attempt_already_exists: "conflict",
        lease_busy: "busy",
        interpretation_slot_already_accepted: "conflict",
        decision_slot_occupied: "conflict",
        decision_partition_capacity_reached: "conflict",
        decision_partition_state_invalid: "conflict",
        decision_revision_changed: "conflict",
        decision_slot_state_invalid: "conflict",
        agent_choice_already_exists: "conflict",
        stale_decision_context: "stale_context",
        decision_context_conflict: "conflict",
        decision_context_limit_reached: "conflict",
        agent_choice_confirmation_required: "confirmation_required",
        candidate_id_already_used: "conflict",
        candidate_head_already_registered: "conflict",
        candidate_not_found: "not_found",
        work_item_not_found: "not_found",
        attempt_not_found: "not_found",
        work_item_already_completed: "conflict",
        attempt_already_completed: "conflict",
        write_set_still_active: "conflict",
        lease_observations_mismatch: "conflict",
        lease_not_active: "conflict",
        candidate_impact_identity_mismatch: "conflict",
        candidate_impact_source_evidence_mismatch: "conflict",
        candidate_impact_surface_already_recorded: "conflict",
        verification_obligation_already_claimed: "conflict",
        verification_obligation_not_found: "not_found",
        verification_obligation_policy_stale: "stale_context",
        verification_obligation_unclaimed: "conflict",
        verification_obligation_claim_stale: "conflict",
        verification_obligation_claim_not_owned: "conflict",
        verification_obligation_claim_expired: "conflict",
        verification_obligation_binding_stale: "stale_context",
        verification_evidence_already_submitted: "conflict",
        verification_evidence_limit_reached: "conflict",
        verification_obligation_terminal: "conflict",
        verification_obligation_waiver_requires_user: "denied",
        verification_obligation_already_waived: "conflict",
        merge_snapshot_id_already_used: "conflict",
        merge_commit_already_registered: "conflict",
        candidate_head_mismatch: "conflict",
        candidate_repository_mismatch: "conflict",
        candidate_target_branch_mismatch: "conflict",
        candidate_object_format_mismatch: "conflict",
        merge_snapshot_not_found: "not_found",
        merge_snapshot_verification_binding_stale: "stale_context",
        merge_snapshot_verification_already_submitted: "conflict",
        merge_snapshot_already_verified: "conflict",
        merge_snapshot_verification_limit_reached: "conflict"
      }.freeze

      def call(result, command_id:)
        structured_content = if result.success?
                               success_content(result.value!)
        else
                               failure_content(result.failure, command_id:)
        end

        ToolResultV1.new(
          content: [
            TextContentV1.new(
              type: "text",
              text: JSON.generate(structured_content.to_h)
            )
          ],
          is_error: result.failure?,
          structured_content:
        )
      end

      private

      def success_content(completion)
        StructuredContentV1.new(
          status: "ok",
          summary: completion.summary,
          command_id: completion.command_id,
          receipt: completion.receipt,
          context_token: nil,
          data: completion.data,
          warnings: completion.warnings,
          next_actions: completion.next_actions
        )
      end

      def failure_content(error, command_id:)
        domain_error = DomainErrorV1::Type[
          {
            code: error.code.to_s,
            message: error.message,
            details: error.details
          }
        ]

        StructuredContentV1.new(
          status: STATUS_BY_CODE.fetch(error.code, "denied"),
          summary: error.message,
          command_id:,
          receipt: nil,
          context_token: nil,
          data: domain_error,
          warnings: [],
          next_actions: failure_next_actions(domain_error)
        )
      end

      def failure_next_actions(domain_error)
        return [] unless domain_error.is_a?(DomainErrorV1::StaleDecisionContextError)

        [
          NextAction.new(
            tool: "decision_resolve",
            arguments: NextAction::DecisionResolutionArguments.new(
              topic_id: domain_error.details.topic_id,
              context: domain_error.details.context
            )
          )
        ]
      end
    end
  end
end
