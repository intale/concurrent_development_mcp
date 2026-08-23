# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetCommandBuilder
      def call(document)
        case document
        when CommandInputDocuments::CreateChangeSetV1
          build_create_change_set(document)
        when CommandInputDocuments::CreateWorkItemV1
          build_create_work_item(document)
        when CommandInputDocuments::DeclareWorkItemDependencyV1
          build_declare_work_item_dependency(document)
        when CommandInputDocuments::ActivateChangeSetV1
          build_activate_change_set(document)
        when CommandInputDocuments::AcquireWorkItemV1
          build_acquire_work_item(document)
        when CommandInputDocuments::ReserveWriteSetV1
          build_reserve_write_set(document)
        when CommandInputDocuments::ExpandWriteSetV1
          build_expand_write_set(document)
        when CommandInputDocuments::RenewLeaseSetV1
          build_renew_lease_set(document)
        when CommandInputDocuments::ReleaseLeaseSetV1
          build_release_lease_set(document)
        when CommandInputDocuments::RecordGuidanceV1
          build_record_guidance(document)
        when CommandInputDocuments::ProposeDecisionInterpretationV1
          build_propose_decision_interpretation(document)
        when CommandInputDocuments::AdjudicateDecisionInterpretationV1
          build_adjudicate_decision_interpretation(document)
        when CommandInputDocuments::ActivateDecisionV1
          build_activate_decision(document)
        when CommandInputDocuments::CorrectDecisionV1
          build_correct_decision(document)
        when CommandInputDocuments::RecordAgentChoiceV1
          build_record_agent_choice(document)
        when CommandInputDocuments::SubmitCandidateV1
          build_submit_candidate(document)
        end
      end

      private

      def build_create_change_set(document)
        input = document.input
        Commands::CreateChangeSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          goal: input.goal,
          acceptance_criteria: input.acceptance_criteria
        )
      end

      def build_create_work_item(document)
        input = document.input
        Commands::CreateWorkItem.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          repository_id: input.repository_id,
          goal: input.goal,
          acceptance_criteria: input.acceptance_criteria
        )
      end

      def build_declare_work_item_dependency(document)
        input = document.input
        Commands::DeclareWorkItemDependency.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          dependency_id: input.dependency_id,
          producer_work_item_id: input.producer_work_item_id,
          consumer_work_item_id: input.consumer_work_item_id,
          dependency_kind: input.dependency_kind,
          required_output: input.required_output
        )
      end

      def build_activate_change_set(document)
        input = document.input
        Commands::ActivateChangeSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id
        )
      end

      def build_acquire_work_item(document)
        input = document.input
        Commands::AcquireWorkItem.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          base_snapshots: input.base_snapshots.map do |snapshot|
            RepositorySnapshotV1.new(snapshot.to_h)
          end
        )
      end

      def build_reserve_write_set(document)
        input = document.input
        Commands::ReserveWriteSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          repository_id: input.repository_id,
          base_commit_oid: input.base_commit_oid,
          resources: input.resources.map { FileResourceV1.new(_1.to_h) },
          lease_duration_seconds: input.lease_duration_seconds
        )
      end

      def build_expand_write_set(document)
        input = document.input
        Commands::ExpandWriteSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          lease_set_id: input.lease_set_id,
          repository_id: input.repository_id,
          base_commit_oid: input.base_commit_oid,
          resources: input.resources.map { FileResourceV1.new(_1.to_h) }
        )
      end

      def build_renew_lease_set(document)
        input = document.input
        Commands::RenewLeaseSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          lease_set_id: input.lease_set_id,
          leases: input.leases.map { LeaseRenewalReferenceV1.new(_1.to_h) },
          lease_duration_seconds: input.lease_duration_seconds
        )
      end

      def build_release_lease_set(document)
        input = document.input
        Commands::ReleaseLeaseSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          lease_set_id: input.lease_set_id,
          leases: input.leases.map { LeaseReleaseReferenceV1.new(_1.to_h) }
        )
      end

      def build_record_guidance(document)
        input = document.input
        Commands::RecordGuidance.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          message_id: input.message_id,
          conversation_id: input.conversation_id,
          source: input.source,
          text: input.text,
          anchors: GuidanceAnchorsV1.new(input.anchors.to_h)
        )
      end

      def build_propose_decision_interpretation(document)
        input = document.input
        Commands::ProposeDecisionInterpretation.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          interpretation_id: input.interpretation_id,
          source_message_id: input.source_message_id,
          source_span: input.source_span,
          classifier: input.classifier,
          proposed_decision: input.proposed_decision,
          ambiguities: input.ambiguities
        )
      end

      def build_adjudicate_decision_interpretation(document)
        input = document.input
        Commands::AdjudicateDecisionInterpretation.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          source_message_id: input.source_message_id,
          interpretation_id: input.interpretation_id,
          action: input.action,
          rationale: input.rationale,
          clarification: input.clarification
        )
      end

      def build_activate_decision(document)
        input = document.input
        Commands::ActivateDecision.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          decision_id: input.decision_id,
          interpretation_id: input.interpretation_id,
          rationale: input.rationale
        )
      end

      def build_correct_decision(document)
        input = document.input
        Commands::CorrectDecision.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          decision_id: input.decision_id,
          interpretation_id: input.interpretation_id,
          expected_head: EventReference.new(input.expected_head.to_h),
          rationale: input.rationale
        )
      end

      def build_record_agent_choice(document)
        input = document.input
        Commands::RecordAgentChoice.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          choice_id: input.choice_id,
          choice_type: input.choice_type,
          selected: input.selected,
          alternatives: input.alternatives,
          reason_summary: input.reason_summary,
          context: input.context,
          decision_context: input.decision_context
        )
      end

      def build_submit_candidate(document)
        input = document.input
        actor = build_actor(input.actor)
        Commands::SubmitCandidate.new(
          command_id: document.command_id,
          actor:,
          candidate_id: input.candidate_id,
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          repository_id: input.repository_id,
          target_branch: input.target_branch,
          object_format: input.object_format,
          base_commit_oid: input.base_commit_oid,
          head_commit_oid: input.head_commit_oid,
          checkpoint_kind: input.checkpoint_kind,
          lease_set_id: input.lease_set_id,
          leases: input.leases.map { Candidates::LeaseObservationV1.new(_1.to_h) },
          manifest: candidate_manifest(input.change_manifest, actor:),
          build_context: candidate_build_context(input.build_context, actor:),
          actual_resources: input.actual_resources.map { FileResourceV1.new(_1.to_h) }
        )
      end

      def candidate_manifest(document, actor:)
        Candidates::ChangeManifestV1.new(
          policy_version: document.policy_version,
          digest: document.digest,
          files: document.files.map { Candidates::ManifestFileV1.new(_1.to_h) },
          collector: candidate_collector(document.collector_version, actor:)
        )
      end

      def candidate_build_context(document, actor:)
        return unless document

        Candidates::BuildContextV1.new(
          policy_version: document.policy_version,
          digest: document.digest,
          inputs: document.inputs.map { Candidates::BuildInputV1.new(_1.to_h) },
          environment: document.environment.map { Candidates::EnvironmentEntryV1.new(_1.to_h) },
          dependency_graph_digest: document.dependency_graph_digest,
          test_environment_digest: document.test_environment_digest,
          collector: candidate_collector(document.collector_version, actor:)
        )
      end

      def candidate_collector(version, actor:)
        Candidates::EvidenceCollectorV1.new(
          kind: actor.kind,
          id: actor.id,
          collector_version: version
        )
      end

      def build_actor(actor)
        Commands::Actor.new(kind: actor.actor_kind, id: actor.actor_id)
      end
    end
  end
end
