# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetCommandBuilder
      def call(document)
        contract = TargetContractRegistry.fetch(document.tool_name)
        contract.input_document_type[document]
        command = send(contract.builder_method, document)
        contract.command_type[command]
      end

      private

      def build_register_repository(document)
        input = document.input
        Commands::RegisterRepository.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          repository_id: input.repository_id,
          scope: input.scope,
          repository_key: input.repository_key,
          display_name: input.display_name,
          paths: input.paths,
          remotes: input.remotes
        )
      end

      def build_resolve_resource(document)
        input = document.input
        Commands::ResolveResource.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          identity: ResourceIdentityNormalizer.new.call(
            repository_id: input.repository_id,
            kind: input.kind,
            path: input.path
          ).value!
        )
      end

      def build_remove_resource(document)
        input = document.input
        Commands::RemoveResource.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          resource_id: input.resource_id,
          reason: input.reason
        )
      end

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

      def build_complete_work_item(document)
        input = document.input
        Commands::CompleteWorkItem.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          candidate_id: input.candidate_id,
          produced_outputs: input.produced_outputs
        )
      end

      def build_abandon_attempt(document)
        input = document.input
        Commands::AbandonAttempt.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          change_set_id: input.change_set_id,
          work_item_id: input.work_item_id,
          attempt_id: input.attempt_id,
          reason: input.reason
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
          resources: input.resources.map { ResourceLeaseTargetV1.new(_1.to_h) },
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
          resources: input.resources.map { ResourceLeaseTargetV1.new(_1.to_h) }
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
          leases: input.leases.map { LeaseRenewalReferenceV2.new(_1.to_h) },
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
          leases: input.leases.map { LeaseReleaseReferenceV2.new(_1.to_h) }
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
          actual_resources: input.actual_resources.map { Candidates::ActualResourceV2.new(_1.to_h) }
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

      def build_submit_candidate_impact_surface(document)
        input = document.input
        Commands::SubmitCandidateImpactSurface.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          candidate_id: input.candidate_id,
          repository_id: input.repository_id,
          head_commit_oid: input.head_commit_oid,
          manifest_digest: input.manifest_digest,
          build_context_digest: input.build_context_digest,
          surface: input.surface
        )
      end

      def build_claim_verification_obligation(document)
        input = document.input
        Commands::ClaimVerificationObligation.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          obligation_id: input.obligation_id,
          claim_duration_seconds: input.claim_duration_seconds
        )
      end

      def build_submit_compatibility_assessment(document)
        input = document.input
        Commands::SubmitCompatibilityAssessment.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          obligation_id: input.obligation_id,
          claim: input.claim,
          binding: input.binding,
          assessment: input.assessment
        )
      end

      def build_waive_verification_obligation(document)
        input = document.input
        Commands::WaiveVerificationObligation.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          obligation_id: input.obligation_id,
          obligation_validity_input_digest: input.obligation_validity_input_digest,
          reason: input.reason
        )
      end

      def build_register_merge_snapshot(document)
        input = document.input
        Commands::RegisterMergeSnapshot.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          merge_snapshot_id: input.merge_snapshot_id,
          repository_id: input.repository_id,
          target_branch: input.target_branch,
          object_format: input.target_base_commit_oid.length == 40 ? "sha1" : "sha256",
          target_base_commit_oid: input.target_base_commit_oid,
          ordered_candidates: input.ordered_candidates.map do |candidate|
            MergeSnapshots::RequestedCandidateV1.new(candidate.to_h)
          end,
          merge_commit_oid: input.merge_commit_oid,
          producer: MergeSnapshots::ProducerV1.new(input.producer.to_h),
          run_id: input.run_id,
          produced_at: input.produced_at,
          policy_version: "merge-snapshot-registration/v1"
        )
      end

      def build_submit_merge_snapshot_verification(document)
        input = document.input
        Commands::SubmitMergeSnapshotVerification.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          merge_snapshot_id: input.merge_snapshot_id,
          binding: input.binding,
          assessment: input.assessment,
          policy_version: "merge-snapshot-verification/v1"
        )
      end

      def build_request_merge_authorization(document)
        input = document.input
        Commands::RequestMergeAuthorization.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          merge_snapshot_id: input.merge_snapshot_id,
          snapshot_binding: input.snapshot_binding,
          target_base_observation: input.target_base_observation,
          expected_impact_policy: input.expected_impact_policy,
          policy_version: "merge-authorization/v1"
        )
      end

      def build_record_merge_observation(document)
        input = document.input
        Commands::RecordMergeObservation.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          merge_snapshot_id: input.merge_snapshot_id,
          authorization_event: EventReference.new(input.authorization_event.to_h),
          authorization_decision_digest: input.authorization_decision_digest,
          repository_id: input.repository_id,
          target_branch: input.target_branch,
          object_format: input.object_format,
          target_before_commit_oid: input.target_before_commit_oid,
          target_after_commit_oid: input.target_after_commit_oid,
          observer: input.observer,
          run_id: input.run_id,
          observed_at: input.observed_at,
          policy_version: "merge-observation/v1"
        )
      end

      def build_prepare_release_set(document)
        input = document.input
        Commands::PrepareReleaseSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          release_set_id: input.release_set_id,
          ordered_members: input.ordered_members,
          policy_version: "release-set-preparation/v1"
        )
      end

      def build_record_repository_integration(document)
        input = document.input
        Commands::RecordRepositoryIntegration.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          release_set_id: input.release_set_id,
          repository_id: input.repository_id,
          attempt_id: input.attempt_id,
          outcome: input.outcome,
          merge_observation_event: input.merge_observation_event &&
            EventReference.new(input.merge_observation_event.to_h),
          observation_digest: input.observation_digest,
          failure: input.failure,
          policy_version: "release-set-integration/v1"
        )
      end

      def build_record_release_set_verification(document)
        input = document.input
        Commands::RecordReleaseSetVerification.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          release_set_id: input.release_set_id,
          integration_events: input.integration_events.map { EventReference.new(_1.to_h) },
          evidence: input.evidence,
          policy_version: "release-set-verification/v1"
        )
      end

      def build_record_release_set_activation(document)
        input = document.input
        Commands::RecordReleaseSetActivation.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          release_set_id: input.release_set_id,
          verification_event: EventReference.new(input.verification_event.to_h),
          verification_digest: input.verification_digest,
          activation_point: input.activation_point,
          policy_version: "release-set-activation/v1"
        )
      end

      def build_complete_compensated_release_set(document)
        input = document.input
        Commands::CompleteCompensatedReleaseSet.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          release_set_id: input.release_set_id,
          compensation_request_event: EventReference.new(input.compensation_request_event.to_h),
          evidence: input.evidence,
          rule_version: "release-set-completion/v1"
        )
      end

      def build_publish_skill_revision(document)
        input = document.input
        Commands::PublishSkillRevision.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          skill_id: input.skill_id,
          name: input.name,
          scope: input.scope,
          expected_revision: input.expected_revision,
          description: input.description,
          instructions: input.instructions,
          assets: input.assets.map { build_skill_asset(_1) },
          content_digest: input.content_digest
        )
      end

      def build_capture_development_artifact(document)
        input = document.input
        artifact_document = input.artifact
        source = DevelopmentArtifacts::SourceV1.new(
          kind: artifact_document.source.kind,
          locator: artifact_document.source.locator,
          revision: artifact_document.source.revision,
          observed_at: artifact_document.source.observed_at,
          collector: artifact_document.source.collector
        )
        artifact = DevelopmentArtifacts::ArtifactV2.new(
          artifact_id: artifact_document.artifact_id,
          scope: artifact_document.scope,
          title: artifact_document.title,
          kind: artifact_document.kind,
          labels: artifact_document.labels,
          content: build_artifact_content(artifact_document.content),
          source:
        )
        Commands::CaptureDevelopmentArtifact.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          artifact:,
          observation: DevelopmentArtifacts::ArtifactObservationV1.new(
            observation_id: artifact_document.observation_id,
            artifact_id: artifact_document.artifact_id,
            scope: artifact_document.scope,
            title: artifact_document.title,
            kind: artifact_document.kind,
            labels: artifact_document.labels,
            source:
          )
        )
      end

      def build_skill_asset(asset)
        return Skills::AssetV2.new(asset.to_h) if asset.is_a?(CommandInputDocuments::SkillAssetV2)

        Skills::AssetV2.new(
          path: asset.path,
          executable: asset.executable,
          content: Content::BinaryV1.new(
            encoding: "binary",
            media_type: asset.media_type,
            base64: asset.content_base64,
            content_sha256: asset.content_sha256,
            byte_size: asset.byte_size
          )
        )
      end

      def build_artifact_content(content)
        return content if content.is_a?(Content::TextV1) || content.is_a?(Content::BinaryV1)

        if content.encoding == "utf-8"
          Content::TextV1.new(
            encoding: "utf-8",
            media_type: content.media_type,
            text: content.content_base64.unpack1("m0").force_encoding(Encoding::UTF_8),
            content_sha256: content.content_sha256,
            byte_size: content.byte_size
          )
        else
          Content::BinaryV1.new(
            encoding: "binary",
            media_type: content.media_type,
            base64: content.content_base64,
            content_sha256: content.content_sha256,
            byte_size: content.byte_size
          )
        end
      end

      def build_correct_development_artifact_classification(document)
        input = document.input
        Commands::CorrectDevelopmentArtifactClassification.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          observation_id: input.observation_id,
          expected_revision: input.expected_revision,
          title: input.title,
          kind: input.kind,
          labels: input.labels,
          reason: input.reason
        )
      end

      def build_declare_development_artifact_relation(document)
        input = document.input
        artifact_relation = input.artifact_relation
        relation_attributes = artifact_relation.relation_attributes
        attribute_values = { path: relation_attributes.path }
        attribute_values[:fragment] = relation_attributes.fragment if relation_attributes.fragment
        if relation_attributes.normalized_locator
          attribute_values[:normalized_locator] = relation_attributes.normalized_locator
        end
        command_values = {
          command_id: document.command_id,
          actor: build_actor(input.actor),
          artifact_relation: DevelopmentArtifacts::RelationV1.new(
            relation_id: artifact_relation.relation_id,
            source_artifact_id: artifact_relation.source_artifact_id,
            relation: artifact_relation.relation,
            target: DevelopmentArtifacts::RelationTargetV1.new(
              kind: artifact_relation.target.kind,
              id: artifact_relation.target.id
            ),
            attributes: DevelopmentArtifacts::RelationAttributesV1.new(**attribute_values)
          )
        }
        if input.supersedes_relation_id
          command_values[:supersedes_relation_id] = input.supersedes_relation_id
          command_values[:supersession_reason] = input.supersession_reason
        end

        Commands::DeclareDevelopmentArtifactRelation.new(**command_values)
      end

      def build_create_operation_batch(document)
        input = document.input
        Commands::CreateOperationBatch.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          batch_id: input.batch_id,
          target_tool: input.target_tool,
          items: input.items,
          manifest_digest: input.manifest_digest,
          encoded_byte_size: input.encoded_byte_size,
          page_size: input.page_size
        )
      end

      def build_cancel_operation_batch(document)
        input = document.input
        Commands::CancelOperationBatch.new(
          command_id: document.command_id,
          actor: build_actor(input.actor),
          batch_id: input.batch_id
        )
      end

      def build_actor(actor)
        Commands::Actor.new(kind: actor.actor_kind, id: actor.actor_id)
      end
    end
  end
end
