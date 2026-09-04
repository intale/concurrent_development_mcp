# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class ToolResultMapper
      STATUS_BY_CODE = DomainErrorV1::ERROR_CODES.to_h { [ _1, "denied" ] }.merge(
        command_id_reused: "command_id_reused",
        repository_already_registered: "conflict",
        repository_identity_conflict: "conflict",
        repository_not_registered: "not_found",
        work_item_unavailable: "conflict",
        attempt_already_exists: "conflict",
        lease_busy: "busy",
        work_intention_conflict: "busy",
        resource_boundary_maintenance_required: "limit_reached",
        resource_history_corrupt: "conflict",
        resource_path_conflict: "conflict",
        resource_not_found: "not_found",
        resource_repository_mismatch: "conflict",
        resource_not_active: "conflict",
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
        skill_identity_conflict: "conflict",
        skill_revision_conflict: "conflict",
        development_artifact_identity_conflict: "conflict",
        development_artifact_observation_identity_conflict: "conflict",
        development_artifact_classification_correction_required: "conflict",
        development_artifact_observation_not_found: "not_found",
        development_artifact_classification_revision_conflict: "conflict",
        development_artifact_revision_conflict: "conflict",
        development_artifact_classification_revision_limit_reached: "limit_reached",
        development_artifact_not_found: "not_found",
        development_artifact_target_not_found: "not_found",
        development_artifact_relation_limit_reached: "limit_reached",
        operation_batch_id_conflict: "conflict",
        operation_batch_not_found: "not_found",
        operation_batch_terminal: "conflict",
        operation_batch_cancellation_already_requested: "conflict",
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
        merge_snapshot_verification_limit_reached: "conflict",
        merge_already_observed: "conflict",
        merge_authorization_not_found: "not_found",
        merge_authorization_binding_stale: "stale_context",
        merge_authorization_stale: "stale_context",
        merge_observation_mismatch: "conflict",
        release_set_id_already_used: "conflict",
        release_set_not_found: "not_found",
        release_set_already_completed: "conflict",
        release_set_compensation_requested: "conflict",
        release_set_already_activated: "conflict",
        release_member_not_found: "not_found",
        release_integration_attempt_reused: "conflict",
        release_member_already_integrated: "conflict",
        release_integration_attempt_limit_reached: "limit_reached",
        release_integration_out_of_order: "conflict",
        release_set_integrations_incomplete: "conflict",
        release_set_already_verified: "conflict",
        release_verification_attempt_limit_reached: "limit_reached",
        release_verification_integration_binding_stale: "stale_context",
        release_set_not_verified: "conflict",
        release_activation_verification_binding_stale: "stale_context",
        release_compensation_not_requested: "conflict",
        release_compensation_request_binding_stale: "stale_context",
        release_set_not_activated: "conflict",
        release_activation_binding_stale: "stale_context",
        release_set_compensation_already_requested: "conflict",
        release_compensation_trigger_not_found: "not_found"
      ).freeze

      def call(result, command_id:, tool_name:)
        contract = TargetContractRegistry.fetch(tool_name)
        structured_content = if result.success?
                               success_content(result.value!, contract:)
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

      def success_content(completion, contract:)
        data = contract.receipt_type[completion.data]
        StructuredContentV1.new(
          status: "ok",
          summary: completion.summary,
          command_id: completion.command_id,
          receipt: completion.receipt,
          context_token: nil,
          data:,
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
          status: STATUS_BY_CODE.fetch(error.code),
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
        if domain_error.is_a?(DomainErrorV1::SkillRevisionConflictError)
          return [
            NextAction.new(
              tool: "skill_get",
              arguments: NextAction::SkillArguments.new(
                name: domain_error.details.name,
                scope: domain_error.details.scope
              )
            )
          ]
        end

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
