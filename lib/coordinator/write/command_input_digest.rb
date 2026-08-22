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

    private

    def actor_document(actor)
      CommandInputDocuments::ActorV1.new(
        actor_kind: actor.kind,
        actor_id: actor.id
      )
    end
  end
end
