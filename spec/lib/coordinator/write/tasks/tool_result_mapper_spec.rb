# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::ToolResultMapper do
  include Dry::Monads[:result]

  subject(:mapper) { described_class.new }

  it "preserves a modeled relation-capacity denial as limit_reached" do
    error = Coordinator::Write::OutcomeError.new(
      code: :development_artifact_relation_limit_reached,
      message: "Development Artifact relation limit reached",
      details: {
        artifact_id: "artifact:v1:#{'a' * 64}",
        relation_count: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT,
        maximum_relation_count: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT
      }
    )

    result = mapper.call(Failure(error), command_id: "cmd-task-result-limit")

    expect(result.structured_content.status).to eq("limit_reached")
    expect(result.is_error).to be(true)
  end

  it "maps every modeled target denial into a strict persisted domain-error shape" do
    examples = [
      [
        :change_set_already_exists,
        { change_set_id: "CS-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError,
        "denied"
      ],
      [
        :dependency_endpoint_missing,
        { change_set_id: "CS-task-result", dependency_id: "DEP-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::ActivationDependencyError,
        "denied"
      ],
      [
        :work_item_already_exists,
        { change_set_id: "CS-task-result", work_item_id: "W-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::WorkItemError,
        "denied"
      ],
      [
        :dependency_id_reused,
        {
          change_set_id: "CS-task-result",
          dependency_id: "DEP-task-result",
          producer_work_item_id: "W-task-result-a",
          consumer_work_item_id: "W-task-result-b"
        },
        Coordinator::Write::Tasks::DomainErrorV1::DependencyError,
        "denied"
      ],
      [
        :work_item_unavailable,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result"
        },
        Coordinator::Write::Tasks::DomainErrorV1::AttemptError,
        "conflict"
      ],
      [
        :command_id_reused,
        {
          command_id: "cmd-task-result",
          existing_tool_name: "change_set_create",
          existing_input_digest: "sha256:#{'a' * 64}",
          requested_tool_name: "change_set_create",
          requested_input_digest: "sha256:#{'b' * 64}"
        },
        Coordinator::Write::Tasks::DomainErrorV1::CommandIdReusedError,
        "command_id_reused"
      ],
      [
        :lease_busy,
        {
          resource_key: "repo:billing:file:app/models/invoice.rb",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          lease_id: "0198e03a-d112-7000-8000-000000000001",
          owner_attempt_id: "ATT-task-result-owner",
          owner_agent_id: "agent-owner",
          fencing_token: 7,
          expires_at: "2026-08-22T10:30:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseBusyError,
        "busy"
      ],
      [
        :write_set_unchanged,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result"
        },
        Coordinator::Write::Tasks::DomainErrorV1::AttemptError,
        "denied"
      ],
      [
        :lease_set_mismatch,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_lease_set_id: "0198e03a-d112-7000-8000-000000000001",
          requested_lease_set_id: "0198e03a-d112-7000-8000-000000000002"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetMismatchError,
        "denied"
      ],
      [
        :resource_evidence_conflict,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key: "repo:billing:file:app/models/invoice.rb",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          current_base_blob_oid: "a" * 40,
          requested_base_blob_oid: "b" * 40
        },
        Coordinator::Write::Tasks::DomainErrorV1::ResourceEvidenceConflictError,
        "denied"
      ],
      [
        :write_set_limit_reached,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_resource_count: 31,
          requested_addition_count: 2
        },
        Coordinator::Write::Tasks::DomainErrorV1::WriteSetLimitError,
        "denied"
      ],
      [
        :lease_set_expired,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          lease_id: "0198e03a-d112-7000-8000-000000000001",
          fencing_token: 7,
          expires_at: "2026-08-22T10:30:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetExpiredError,
        "denied"
      ],
      [
        :lease_set_not_current,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          expected_lease_id: "0198e03a-d112-7000-8000-000000000001",
          current_lease_id: "0198e03a-d112-7000-8000-000000000002",
          expected_fencing_token: 7,
          current_fencing_token: 8,
          current_lease_set_id: "0198e03a-d112-7000-8000-000000000003",
          current_attempt_id: "ATT-task-result-other",
          current_expires_at: "2026-08-22T10:45:00.000000Z",
          current_released_at: nil,
          current_expired_at: nil
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetNotCurrentError,
        "denied"
      ],
      [
        :write_set_released,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          released_at: "2026-08-22T10:40:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::WriteSetReleasedError,
        "denied"
      ],
      [
        :lease_set_snapshot_mismatch,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_resource_key_hashes: [ "sha256:#{'a' * 64}" ],
          requested_resource_key_hashes: [ "sha256:#{'b' * 64}" ]
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetSnapshotMismatchError,
        "denied"
      ],
      [
        :lease_reference_mismatch,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key_hash: "sha256:#{'a' * 64}",
          current_lease_id: "0198e03a-d112-7000-8000-000000000001",
          requested_lease_id: "0198e03a-d112-7000-8000-000000000002",
          current_fencing_token: 7,
          requested_fencing_token: 6
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseReferenceMismatchError,
        "denied"
      ],
      [
        :lease_deadline_not_extended,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_expires_at: "2026-08-22T10:30:00.000000Z",
          requested_expires_at: "2026-08-22T10:29:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseDeadlineNotExtendedError,
        "denied"
      ],
      [
        :message_already_recorded,
        { message_id: "M-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::MessageAlreadyRecordedError,
        "denied"
      ],
      [
        :interpretation_not_found,
        { interpretation_id: "I-task-result", message_id: "M-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::InterpretationNotFoundError,
        "denied"
      ],
      [
        :interpretation_already_accepted,
        {
          interpretation_id: "I-task-result",
          event_id: "0198e03a-d112-7000-8000-000000000001"
        },
        Coordinator::Write::Tasks::DomainErrorV1::InterpretationAlreadyAcceptedError,
        "denied"
      ],
      [
        :interpretation_already_rejected,
        {
          interpretation_id: "I-task-result",
          event_id: "0198e03a-d112-7000-8000-000000000001"
        },
        Coordinator::Write::Tasks::DomainErrorV1::InterpretationAlreadyRejectedError,
        "denied"
      ],
      [
        :interpretation_slot_already_accepted,
        {
          interpretation_id: "I-task-result-other",
          event_id: "0198e03a-d112-7000-8000-000000000001",
          slot_digest: "sha256:#{'a' * 64}"
        },
        Coordinator::Write::Tasks::DomainErrorV1::InterpretationSlotAlreadyAcceptedError,
        "conflict"
      ],
      [
        :interpretation_not_accepted,
        { interpretation_id: "I-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::InterpretationNotAcceptedError,
        "denied"
      ],
      [
        :decision_already_exists,
        {
          decision_id: "D-task-result",
          event_id: "0198e03a-d112-7000-8000-000000000001",
          event_type: "DecisionRecorded"
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionAlreadyExistsError,
        "denied"
      ],
      [
        :interpretation_already_activated,
        {
          interpretation_id: "I-task-result",
          decision_id: "D-task-result",
          event_id: "0198e03a-d112-7000-8000-000000000001"
        },
        Coordinator::Write::Tasks::DomainErrorV1::InterpretationAlreadyActivatedError,
        "denied"
      ],
      [
        :decision_definition_not_activatable,
        { reasons: [ "scope_unresolved" ] },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionDefinitionNotActivatableError,
        "denied"
      ],
      [
        :decision_slot_occupied,
        {
          slot_id: "compound:decision-slot:v1:sha256:#{'a' * 64}",
          decision_id: "D-task-result",
          event_id: "0198e03a-d112-7000-8000-000000000001"
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionSlotOccupiedError,
        "conflict"
      ],
      [
        :decision_partition_limit_reached,
        {
          decision_id: "D-task-result",
          partition_count: 33,
          maximum_partition_count: 32
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionPartitionLimitReachedError,
        "denied"
      ],
      [
        :decision_partition_capacity_reached,
        {
          partition_id: "repo:billing:testing",
          active_decision_count: 32,
          maximum_active_decisions: 32
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionPartitionCapacityReachedError,
        "conflict"
      ],
      [
        :decision_partition_state_invalid,
        {
          partition_id: "repo:billing:testing",
          decision_id: "D-task-result",
          expected_head: {
            decision_id: "D-task-result",
            decision_revision: 1,
            event: {
              event_id: "0198e03a-d112-7000-8000-000000000001",
              type: "DecisionActivated",
              stream_context: "HumanGuidance",
              stream_name: "Decision",
              stream_id: "D-task-result",
              stream_revision: 1
            }
          },
          observed_head: nil
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionPartitionStateInvalidError,
        "conflict"
      ],
      [
        :decision_not_found,
        { decision_id: "D-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionNotFoundError,
        "denied"
      ],
      [
        :decision_not_active,
        {
          decision_id: "D-task-result",
          event: {
            event_id: "0198e03a-d112-7000-8000-000000000001",
            type: "DecisionRecorded",
            stream_context: "HumanGuidance",
            stream_name: "Decision",
            stream_id: "D-task-result",
            stream_revision: 0
          }
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionNotActiveError,
        "denied"
      ],
      [
        :interpretation_not_a_correction,
        {
          interpretation_id: "I-task-result",
          decision_id: "D-task-result",
          relations: {
            corrects: [],
            supersedes: [ "D-task-result" ],
            exception_to: [],
            revokes: []
          }
        },
        Coordinator::Write::Tasks::DomainErrorV1::InterpretationNotACorrectionError,
        "denied"
      ],
      [
        :decision_definition_not_correctable,
        { reasons: [ "validity_future" ] },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionDefinitionNotCorrectableError,
        "denied"
      ],
      [
        :decision_revision_changed,
        {
          decision_id: "D-task-result",
          expected_head: {
            event_id: "0198e03a-d112-7000-8000-000000000001",
            type: "DecisionActivated",
            stream_context: "HumanGuidance",
            stream_name: "Decision",
            stream_id: "D-task-result",
            stream_revision: 1
          },
          current_head: {
            event_id: "0198e03a-d112-7000-8000-000000000002",
            type: "DecisionDefinitionCorrected",
            stream_context: "HumanGuidance",
            stream_name: "Decision",
            stream_id: "D-task-result",
            stream_revision: 2
          }
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionRevisionChangedError,
        "conflict"
      ],
      [
        :decision_slot_state_invalid,
        {
          slot_id: "compound:decision-slot:v1:sha256:#{'a' * 64}",
          head: nil
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionSlotStateInvalidError,
        "conflict"
      ],
      [
        :agent_choice_already_exists,
        {
          choice_id: "CHO-task-result",
          recorded_event: event_reference(
            event_id: "0198e03a-d112-7000-8000-000000000010",
            type: "AgentChoiceRecorded",
            stream_context: "AgentGovernance",
            stream_name: "AgentChoice",
            stream_id: "CHO-task-result",
            stream_revision: 0
          )
        },
        Coordinator::Write::Tasks::DomainErrorV1::AgentChoiceAlreadyExistsError,
        "conflict"
      ],
      [
        :stale_decision_context,
        {
          changed_partition_ids: [ "repo:billing:testing" ],
          submitted_digest: "sha256:#{'a' * 64}",
          current_digest: "sha256:#{'b' * 64}",
          topic_id: "testing.framework",
          context: decision_query_context
        },
        Coordinator::Write::Tasks::DomainErrorV1::StaleDecisionContextError,
        "stale_context"
      ],
      [
        :decision_context_mismatch,
        {
          submitted_digest: "sha256:#{'a' * 64}",
          current_digest: "sha256:#{'b' * 64}"
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionContextMismatchError,
        "denied"
      ],
      [
        :decision_context_conflict,
        {
          conflict: {
            decisions: [ resolved_decision("D-task-result-a"), resolved_decision("D-task-result-b") ],
            reason: "tied_most_specific"
          }
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionContextConflictError,
        "conflict"
      ],
      [
        :decision_context_limit_reached,
        {
          partition_count: 5,
          maximum_partition_count: 8,
          active_decision_count: 33,
          maximum_active_decision_count: 32
        },
        Coordinator::Write::Tasks::DomainErrorV1::DecisionContextLimitReachedError,
        "conflict"
      ],
      [
        :unsupported_decision_context,
        {
          dimensions: [ "value.schema" ],
          decision_heads: [ decision_head("D-task-result") ]
        },
        Coordinator::Write::Tasks::DomainErrorV1::UnsupportedDecisionContextError,
        "denied"
      ],
      [
        :agent_choice_blocked_by_decision,
        policy_details(on_violation: "block"),
        Coordinator::Write::Tasks::DomainErrorV1::AgentChoiceBlockedByDecisionError,
        "denied"
      ],
      [
        :agent_choice_confirmation_required,
        policy_details(on_violation: "require_confirmation"),
        Coordinator::Write::Tasks::DomainErrorV1::AgentChoiceConfirmationRequiredError,
        "confirmation_required"
      ],
      [
        :decision_partition_state_invalid,
        {
          partition_id: "repo:billing:testing",
          stream_revision: 2,
          reason: "snapshot_invariant_violated"
        },
        Coordinator::Write::Tasks::DomainErrorV1::AgentChoicePartitionSnapshotInvalidError,
        "conflict"
      ],
      [
        :decision_partition_state_invalid,
        {
          decision_id: "D-task-result",
          expected_head: decision_head("D-task-result"),
          current_head: nil
        },
        Coordinator::Write::Tasks::DomainErrorV1::AgentChoiceDecisionHeadInvalidError,
        "conflict"
      ],
      [
        :decision_partition_state_invalid,
        { decision_heads: [ decision_head("D-task-result") ] },
        Coordinator::Write::Tasks::DomainErrorV1::AgentChoiceUnresolvedHeadsError,
        "conflict"
      ],
      [
        :candidate_id_already_used,
        {
          candidate_id: "CAN-task-result",
          existing_event: candidate_event_reference("CAN-task-result")
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateAlreadyExistsError,
        "conflict"
      ],
      [
        :candidate_head_already_registered,
        {
          candidate_id: "CAN-task-result",
          repository_id: "billing",
          object_format: "sha1",
          head_commit_oid: "b" * 40,
          existing_event: event_reference(
            event_id: "0198e03a-d112-7000-8000-000000000021",
            type: "CandidateHeadRegistered",
            stream_context: "DevelopmentIntegration",
            stream_name: "CandidateHead",
            stream_id: "sha256:#{'c' * 64}",
            stream_revision: 0
          )
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateHeadAlreadyRegisteredError,
        "conflict"
      ],
      [
        :lease_observations_mismatch,
        {
          attempt_id: "A-task-result",
          expected_resource_key_hashes: [ "sha256:#{'a' * 64}" ],
          submitted_resource_key_hashes: [ "sha256:#{'b' * 64}" ]
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateLeaseObservationsMismatchError,
        "conflict"
      ],
      [
        :lease_not_active,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "A-task-result"
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateLeaseNotActiveScopeError,
        "conflict"
      ],
      [
        :lease_not_active,
        {
          attempt_id: "A-task-result",
          resource_key_hash: "sha256:#{'a' * 64}",
          submitted_lease_id: "0198e03a-d112-7000-8000-000000000001",
          current_lease_id: "0198e03a-d112-7000-8000-000000000002",
          current_fencing_token: 2,
          expires_at: "2026-08-22T10:30:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateLeaseNotActiveError,
        "conflict"
      ],
      [
        :actual_write_set_not_authorized,
        {
          candidate_id: "CAN-task-result",
          resources: [
            { resource_key_hash: "sha256:#{'a' * 64}", path: "lib/candidate.rb" }
          ]
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateUnauthorizedResourcesError,
        "denied"
      ],
      [
        :manifest_base_evidence_mismatch,
        {
          candidate_id: "CAN-task-result",
          resource_key_hash: "sha256:#{'a' * 64}",
          path: "lib/candidate.rb",
          expected_base_blob_oid: "a" * 40,
          submitted_base_blob_oid: "b" * 40
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateManifestBaseMismatchError,
        "denied"
      ],
      [
        :candidate_not_found,
        { candidate_id: "CAN-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateNotFoundError,
        "not_found"
      ],
      [
        :candidate_impact_identity_mismatch,
        {
          candidate_id: "CAN-task-result",
          expected_repository_id: "billing",
          expected_head_commit_oid: "b" * 40,
          submitted_repository_id: "other",
          submitted_head_commit_oid: "c" * 40
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateImpactIdentityMismatchError,
        "conflict"
      ],
      [
        :candidate_impact_source_evidence_mismatch,
        {
          candidate_id: "CAN-task-result",
          expected_manifest_digest: "sha256:#{"a" * 64}",
          submitted_manifest_digest: "sha256:#{"b" * 64}",
          expected_build_context_digest: nil,
          submitted_build_context_digest: nil
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateImpactSourceEvidenceMismatchError,
        "conflict"
      ],
      [
        :candidate_impact_surface_already_recorded,
        {
          candidate_id: "CAN-task-result",
          existing_event: event_reference(
            event_id: "0198e03a-d112-7000-8000-000000000022",
            type: "CandidateImpactSurfaceDerived",
            stream_context: "DevelopmentIntegration",
            stream_name: "Candidate",
            stream_id: "CAN-task-result",
            stream_revision: 3
          )
        },
        Coordinator::Write::Tasks::DomainErrorV1::CandidateImpactSurfaceAlreadyRecordedError,
        "conflict"
      ]
    ]

    examples.each do |code, details, error_class, status|
      error = Coordinator::Write::OutcomeError.new(
        code:,
        message: "The target command was denied",
        details:
      )

      result = mapper.call(Failure(error), command_id: "cmd-task-result")

      expect(result.is_error).to be(true)
      expect(result.structured_content.status).to eq(status)
      expect(result.structured_content.data).to be_a(error_class)
      expected_actions = code == :stale_decision_context ? [ "decision_resolve" ] : []
      expect(result.structured_content.next_actions.map(&:tool)).to eq(expected_actions)
      if code == :stale_decision_context
        expect(result.structured_content.next_actions.sole.arguments).to have_attributes(
          topic_id: "testing.framework",
          context: Coordinator::Write::DecisionContexts::QueryContextV1.new(decision_query_context)
        )
      end
      expect(JSON.parse(result.content.sole.text)).to eq(
        JSON.parse(JSON.generate(result.structured_content.to_h))
      )
    end
  end

  it "maps every WorkItem completion denial without turning a public conflict into an execution fault" do
    common_details = {
      change_set_id: "CS-task-completion",
      work_item_id: "W-task-completion",
      attempt_id: "ATT-task-completion",
      candidate_id: "CAN-task-completion"
    }
    common_codes = %i[
      change_set_not_active
      work_item_not_found
      work_item_scope_mismatch
      work_item_already_completed
      work_item_not_active
      attempt_owner_mismatch
      attempt_not_found
      attempt_already_completed
      attempt_scope_mismatch
      candidate_not_found
      candidate_scope_mismatch
      candidate_actor_mismatch
      candidate_not_final
      write_set_not_reserved
    ]

    common_codes.each do |code|
      result = mapper.call(
        Failure(
          Coordinator::Write::OutcomeError.new(
            code:,
            message: "WorkItem completion was denied",
            details: common_details
          )
        ),
        command_id: "cmd-task-completion-#{code}"
      )

      expect(result.structured_content.data).to be_a(
        Coordinator::Write::Tasks::DomainErrorV1::WorkItemCompletionError
      )
      expect(result.is_error).to be(true)
    end

    active = mapper.call(
      Failure(
        Coordinator::Write::OutcomeError.new(
          code: :write_set_still_active,
          message: "Release the write set before completion",
          details: common_details.merge(
            lease_set_id: "0198e03a-d112-7000-8000-000000000001",
            expires_at: "2026-08-22T10:30:00.000000Z"
          )
        )
      ),
      command_id: "cmd-task-completion-active-write-set"
    )

    expect(active.structured_content).to have_attributes(status: "conflict")
    expect(active.structured_content.data).to be_a(
      Coordinator::Write::Tasks::DomainErrorV1::WorkItemCompletionActiveWriteSetError
    )
    expect(active.is_error).to be(true)
  end

  def event_reference(event_id:, type:, stream_context:, stream_name:, stream_id:, stream_revision:)
    {
      event_id:,
      type:,
      stream_context:,
      stream_name:,
      stream_id:,
      stream_revision:
    }
  end

  def decision_head(decision_id)
    {
      decision_id:,
      decision_revision: 1,
      event: event_reference(
        event_id: "0198e03a-d112-7000-8000-000000000011",
        type: "DecisionActivated",
        stream_context: "HumanGuidance",
        stream_name: "Decision",
        stream_id: decision_id,
        stream_revision: 1
      )
    }
  end

  def candidate_event_reference(candidate_id)
    event_reference(
      event_id: "0198e03a-d112-7000-8000-000000000020",
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: candidate_id,
      stream_revision: 0
    )
  end

  def resolved_decision(decision_id)
    {
      head: decision_head(decision_id),
      definition_digest: "sha256:#{'c' * 64}",
      topic_id: "testing.framework",
      effect: "require",
      modality: "must",
      value: {
        schema: "named-choice/v1",
        name: "rspec",
        items: nil,
        target_kind: nil,
        target_id: nil,
        action: nil
      },
      enforcement: {
        level: "implementation_gate",
        retroactivity: "future_only",
        on_violation: "block"
      },
      anchor_kind: "repository",
      anchor_rank: 2,
      applicability_reasons: [ "repository" ]
    }
  end

  def policy_details(on_violation:)
    {
      decision_head: decision_head("D-task-result"),
      effect: "require",
      selected_option_id: "minitest",
      decision_option_id: "rspec",
      on_violation:
    }
  end

  def decision_query_context
    {
      workspace_id: nil,
      repository_id: "billing",
      change_set_id: "CS-task-result",
      work_item_id: "W-task-result",
      attempt_id: "A-task-result",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/order_spec.rb" ],
      environment: "test",
      agent_role: "implementer"
    }
  end
end
