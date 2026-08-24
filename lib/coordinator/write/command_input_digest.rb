# frozen_string_literal: true

module Coordinator::Write
  class CommandInputDigest
    def initialize(canonical_json: CanonicalJson.new)
      @canonical_json = canonical_json
    end

    def call(command)
      @canonical_json.sha256(document(command).to_h)
    end

    def document(command)
      case command
      when Commands::CreateChangeSet then create_change_set_document(command)
      when Commands::CreateWorkItem then work_item_create_document(command)
      when Commands::DeclareWorkItemDependency then work_item_dependency_declare_document(command)
      when Commands::ActivateChangeSet then change_set_activate_document(command)
      when Commands::AcquireWorkItem then work_item_acquire_document(command)
      when Commands::ReserveWriteSet then write_set_reserve_document(command)
      when Commands::ExpandWriteSet then write_set_expand_document(command)
      when Commands::RenewLeaseSet then lease_renew_document(command)
      when Commands::ReleaseLeaseSet then lease_release_document(command)
      when Commands::RecordGuidance then guidance_record_document(command)
      when Commands::ProposeDecisionInterpretation then decision_interpretation_propose_document(command)
      when Commands::AdjudicateDecisionInterpretation then decision_interpretation_adjudicate_document(command)
      when Commands::ActivateDecision then decision_activate_document(command)
      when Commands::CorrectDecision then decision_correct_document(command)
      when Commands::RecordAgentChoice then agent_choice_record_document(command)
      when Commands::SubmitCandidate then candidate_submit_document(command)
      when Commands::SubmitCandidateImpactSurface then candidate_impact_surface_submit_document(command)
      when Commands::ClaimVerificationObligation then verification_obligation_claim_document(command)
      when Commands::SubmitCompatibilityAssessment then compatibility_assessment_submit_document(command)
      when Commands::WaiveVerificationObligation then verification_obligation_waive_document(command)
      when Commands::RegisterMergeSnapshot then merge_snapshot_register_document(command)
      when Commands::SubmitMergeSnapshotVerification then merge_verification_submit_document(command)
      when Commands::ExpireResourceLease then lease_expire_policy_document(command)
      else
        raise ArgumentError, "Unsupported coordination command: #{command.class.name}"
      end
    end

    def create_change_set(command)
      @canonical_json.sha256(create_change_set_document(command).to_h)
    end

    def create_change_set_document(command)
      CommandInputDocuments::CreateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "change_set_create",
        input: CommandInputDocuments::CreateChangeSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          goal: command.goal,
          acceptance_criteria: command.acceptance_criteria
        )
      )
    end

    def work_item_create(command)
      @canonical_json.sha256(work_item_create_document(command).to_h)
    end

    def work_item_create_document(command)
      CommandInputDocuments::CreateWorkItemV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "work_item_create",
        input: CommandInputDocuments::CreateWorkItemInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          repository_id: command.repository_id,
          goal: command.goal,
          acceptance_criteria: command.acceptance_criteria
        )
      )
    end

    def work_item_dependency_declare(command)
      @canonical_json.sha256(work_item_dependency_declare_document(command).to_h)
    end

    def work_item_dependency_declare_document(command)
      CommandInputDocuments::DeclareWorkItemDependencyV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "work_item_dependency_declare",
        input: CommandInputDocuments::DeclareWorkItemDependencyInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          dependency_id: command.dependency_id,
          producer_work_item_id: command.producer_work_item_id,
          consumer_work_item_id: command.consumer_work_item_id,
          dependency_kind: command.dependency_kind,
          required_output: command.required_output
        )
      )
    end

    def change_set_activate(command)
      @canonical_json.sha256(change_set_activate_document(command).to_h)
    end

    def change_set_activate_document(command)
      CommandInputDocuments::ActivateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "change_set_activate",
        input: CommandInputDocuments::ActivateChangeSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id
        )
      )
    end

    def work_item_acquire(command)
      @canonical_json.sha256(work_item_acquire_document(command).to_h)
    end

    def work_item_acquire_document(command)
      CommandInputDocuments::AcquireWorkItemV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "work_item_acquire",
        input: CommandInputDocuments::AcquireWorkItemInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          base_snapshots: command.base_snapshots.map do |snapshot|
            CommandInputDocuments::RepositorySnapshotV1.new(snapshot.to_h)
          end
        )
      )
    end

    def write_set_reserve(command)
      @canonical_json.sha256(write_set_reserve_document(command).to_h)
    end

    def write_set_reserve_document(command)
      CommandInputDocuments::ReserveWriteSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "write_set_reserve",
        input: CommandInputDocuments::ReserveWriteSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          base_commit_oid: command.base_commit_oid,
          resources: command.resources.map do |resource|
            CommandInputDocuments::FileResourceV1.new(resource.to_h)
          end,
          lease_duration_seconds: command.lease_duration_seconds
        )
      )
    end

    def write_set_expand(command)
      @canonical_json.sha256(write_set_expand_document(command).to_h)
    end

    def write_set_expand_document(command)
      CommandInputDocuments::ExpandWriteSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "write_set_expand",
        input: CommandInputDocuments::ExpandWriteSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          lease_set_id: command.lease_set_id,
          repository_id: command.repository_id,
          base_commit_oid: command.base_commit_oid,
          resources: command.resources.map do |resource|
            CommandInputDocuments::FileResourceV1.new(resource.to_h)
          end
        )
      )
    end

    def lease_renew(command)
      @canonical_json.sha256(lease_renew_document(command).to_h)
    end

    def lease_renew_document(command)
      CommandInputDocuments::RenewLeaseSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "lease_renew",
        input: CommandInputDocuments::RenewLeaseSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          lease_set_id: command.lease_set_id,
          leases: command.leases.map do |reference|
            CommandInputDocuments::LeaseRenewalReferenceV1.new(reference.to_h)
          end,
          lease_duration_seconds: command.lease_duration_seconds
        )
      )
    end

    def lease_release(command)
      @canonical_json.sha256(lease_release_document(command).to_h)
    end

    def lease_release_document(command)
      CommandInputDocuments::ReleaseLeaseSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "lease_release",
        input: CommandInputDocuments::ReleaseLeaseSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          lease_set_id: command.lease_set_id,
          leases: command.leases.map do |reference|
            CommandInputDocuments::LeaseReleaseReferenceV1.new(reference.to_h)
          end
        )
      )
    end

    def lease_expire_policy(command)
      @canonical_json.sha256(lease_expire_policy_document(command).to_h)
    end

    def lease_expire_policy_document(command)
      CommandInputDocuments::ExpireResourceLeaseV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "lease_expire_policy",
        input: CommandInputDocuments::ExpireResourceLeaseInputV1.new(
          actor: actor_document(command.actor),
          resource_key_hash: command.resource_key_hash,
          lease_id: command.lease_id,
          lease_set_id: command.lease_set_id,
          fencing_token: command.fencing_token,
          expected_expires_at: command.expected_expires_at
        )
      )
    end

    def guidance_record(command)
      @canonical_json.sha256(guidance_record_document(command).to_h)
    end

    def guidance_record_document(command)
      CommandInputDocuments::RecordGuidanceV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "guidance_record",
        input: CommandInputDocuments::RecordGuidanceInputV1.new(
          actor: actor_document(command.actor),
          message_id: command.message_id,
          conversation_id: command.conversation_id,
          source: command.source,
          text: command.text,
          anchors: CommandInputDocuments::GuidanceAnchorsV1.new(command.anchors.to_h)
        )
      )
    end

    def decision_interpretation_propose(command)
      @canonical_json.sha256(decision_interpretation_propose_document(command).to_h)
    end

    def decision_interpretation_propose_document(command)
      CommandInputDocuments::ProposeDecisionInterpretationV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "decision_interpretation_propose",
        input: CommandInputDocuments::ProposeDecisionInterpretationInputV1.new(
          actor: actor_document(command.actor),
          interpretation_id: command.interpretation_id,
          source_message_id: command.source_message_id,
          source_span: command.source_span,
          classifier: command.classifier,
          proposed_decision: command.proposed_decision,
          ambiguities: command.ambiguities
        )
      )
    end

    def decision_interpretation_adjudicate(command)
      @canonical_json.sha256(decision_interpretation_adjudicate_document(command).to_h)
    end

    def decision_interpretation_adjudicate_document(command)
      CommandInputDocuments::AdjudicateDecisionInterpretationV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "decision_interpretation_adjudicate",
        input: CommandInputDocuments::AdjudicateDecisionInterpretationInputV1.new(
          actor: actor_document(command.actor),
          source_message_id: command.source_message_id,
          interpretation_id: command.interpretation_id,
          action: command.action,
          rationale: command.rationale,
          clarification: command.clarification
        )
      )
    end

    def decision_activate(command)
      @canonical_json.sha256(decision_activate_document(command).to_h)
    end

    def decision_activate_document(command)
      CommandInputDocuments::ActivateDecisionV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "decision_activate",
        input: CommandInputDocuments::ActivateDecisionInputV1.new(
          actor: actor_document(command.actor),
          decision_id: command.decision_id,
          interpretation_id: command.interpretation_id,
          rationale: command.rationale
        )
      )
    end

    def decision_correct(command)
      @canonical_json.sha256(decision_correct_document(command).to_h)
    end

    def decision_correct_document(command)
      CommandInputDocuments::CorrectDecisionV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "decision_correct",
        input: CommandInputDocuments::CorrectDecisionInputV1.new(
          actor: actor_document(command.actor),
          decision_id: command.decision_id,
          interpretation_id: command.interpretation_id,
          expected_head: CommandInputDocuments::EventReferenceV1.new(command.expected_head.to_h),
          rationale: command.rationale
        )
      )
    end

    def agent_choice_record(command)
      @canonical_json.sha256(agent_choice_record_document(command).to_h)
    end

    def agent_choice_record_document(command)
      CommandInputDocuments::RecordAgentChoiceV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "agent_choice_record",
        input: CommandInputDocuments::RecordAgentChoiceInputV1.new(
          actor: actor_document(command.actor),
          choice_id: command.choice_id,
          choice_type: command.choice_type,
          selected: command.selected,
          alternatives: command.alternatives,
          reason_summary: command.reason_summary,
          context: command.context,
          decision_context: command.decision_context
        )
      )
    end

    def candidate_submit(command)
      @canonical_json.sha256(candidate_submit_document(command).to_h)
    end

    def candidate_submit_document(command)
      CommandInputDocuments::SubmitCandidateV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "candidate_submit",
        input: CommandInputDocuments::SubmitCandidateInputV1.new(
          actor: actor_document(command.actor),
          candidate_id: command.candidate_id,
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          base_commit_oid: command.base_commit_oid,
          head_commit_oid: command.head_commit_oid,
          checkpoint_kind: command.checkpoint_kind,
          lease_set_id: command.lease_set_id,
          leases: command.leases.map do |lease|
            CommandInputDocuments::CandidateLeaseObservationV1.new(
              resource_key_hash: lease.resource_key_hash,
              lease_id: lease.lease_id,
              fencing_token: lease.fencing_token
            )
          end,
          change_manifest: candidate_manifest_document(command.manifest),
          build_context: candidate_build_context_document(command.build_context),
          actual_resources: command.actual_resources.map do |resource|
            CommandInputDocuments::FileResourceV1.new(resource.to_h)
          end
        )
      )
    end

    def candidate_impact_surface_submit(command)
      @canonical_json.sha256(candidate_impact_surface_submit_document(command).to_h)
    end

    def candidate_impact_surface_submit_document(command)
      CommandInputDocuments::SubmitCandidateImpactSurfaceV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "candidate_impact_surface_submit",
        input: CommandInputDocuments::SubmitCandidateImpactSurfaceInputV1.new(
          actor: actor_document(command.actor),
          candidate_id: command.candidate_id,
          repository_id: command.repository_id,
          head_commit_oid: command.head_commit_oid,
          manifest_digest: command.manifest_digest,
          build_context_digest: command.build_context_digest,
          surface: command.surface
        )
      )
    end

    def verification_obligation_claim(command)
      @canonical_json.sha256(verification_obligation_claim_document(command).to_h)
    end

    def verification_obligation_claim_document(command)
      CommandInputDocuments::ClaimVerificationObligationV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "verification_obligation_claim",
        input: CommandInputDocuments::ClaimVerificationObligationInputV1.new(
          actor: actor_document(command.actor),
          obligation_id: command.obligation_id,
          claim_duration_seconds: command.claim_duration_seconds
        )
      )
    end

    def compatibility_assessment_submit(command)
      @canonical_json.sha256(compatibility_assessment_submit_document(command).to_h)
    end

    def compatibility_assessment_submit_document(command)
      CommandInputDocuments::SubmitCompatibilityAssessmentV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "compatibility_assessment_submit",
        input: CommandInputDocuments::SubmitCompatibilityAssessmentInputV1.new(
          actor: actor_document(command.actor),
          obligation_id: command.obligation_id,
          claim: command.claim,
          binding: command.binding,
          assessment: command.assessment
        )
      )
    end

    def verification_obligation_waive(command)
      @canonical_json.sha256(verification_obligation_waive_document(command).to_h)
    end

    def verification_obligation_waive_document(command)
      CommandInputDocuments::WaiveVerificationObligationV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "verification_obligation_waive",
        input: CommandInputDocuments::WaiveVerificationObligationInputV1.new(
          actor: actor_document(command.actor),
          obligation_id: command.obligation_id,
          obligation_validity_input_digest: command.obligation_validity_input_digest,
          reason: command.reason
        )
      )
    end

    def merge_snapshot_register(command)
      @canonical_json.sha256(merge_snapshot_register_document(command).to_h)
    end

    def merge_snapshot_register_document(command)
      CommandInputDocuments::RegisterMergeSnapshotV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "merge_snapshot_register",
        input: CommandInputDocuments::RegisterMergeSnapshotInputV1.new(
          actor: actor_document(command.actor),
          merge_snapshot_id: command.merge_snapshot_id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          target_base_commit_oid: command.target_base_commit_oid,
          ordered_candidates: command.ordered_candidates.map do |candidate|
            CommandInputDocuments::MergeSnapshotCandidateV1.new(candidate.to_h)
          end,
          merge_commit_oid: command.merge_commit_oid,
          producer: CommandInputDocuments::MergeSnapshotProducerV1.new(command.producer.to_h),
          run_id: command.run_id,
          produced_at: command.produced_at
        )
      )
    end

    def merge_verification_submit(command)
      @canonical_json.sha256(merge_verification_submit_document(command).to_h)
    end

    def merge_verification_submit_document(command)
      CommandInputDocuments::SubmitMergeSnapshotVerificationV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "merge_verification_submit",
        input: CommandInputDocuments::SubmitMergeSnapshotVerificationInputV1.new(
          actor: actor_document(command.actor),
          merge_snapshot_id: command.merge_snapshot_id,
          binding: command.binding,
          assessment: command.assessment
        )
      )
    end

    private

    def candidate_manifest_document(manifest)
      CommandInputDocuments::CandidateChangeManifestV1.new(
        policy_version: manifest.policy_version,
        digest: manifest.digest,
        collector_version: manifest.collector.collector_version,
        files: manifest.files.map do |file|
          CommandInputDocuments::CandidateManifestFileV1.new(
            status: file.status,
            old_path: file.old_path,
            new_path: file.new_path,
            old_blob_oid: file.old_blob_oid,
            new_blob_oid: file.new_blob_oid,
            old_mode: file.old_mode,
            new_mode: file.new_mode
          )
        end
      )
    end

    def candidate_build_context_document(context)
      return unless context

      CommandInputDocuments::CandidateBuildContextV1.new(
        policy_version: context.policy_version,
        digest: context.digest,
        collector_version: context.collector.collector_version,
        inputs: context.inputs.map do |input|
          CommandInputDocuments::CandidateBuildInputV1.new(
            kind: input.kind,
            path: input.path,
            blob_oid: input.blob_oid
          )
        end,
        environment: context.environment.map do |entry|
          CommandInputDocuments::CandidateEnvironmentEntryV1.new(
            name: entry.name,
            value: entry.value
          )
        end,
        dependency_graph_digest: context.dependency_graph_digest,
        test_environment_digest: context.test_environment_digest
      )
    end

    def actor_document(actor)
      CommandInputDocuments::ActorV1.new(
        actor_kind: actor.kind,
        actor_id: actor.id
      )
    end
  end
end
