# frozen_string_literal: true

module Coordinator
  class Container < Dry::System::Container
    register("canonical_json", memoize: true) { Shared::CanonicalJson.new }
    register("compound_marker_builder", memoize: true) do
      Shared::CompoundMarkerBuilder.new(canonical_json: self["canonical_json"])
    end
    register("clock", memoize: true) { Shared::SystemClock.new }
    register("id_generator", memoize: true) { Shared::IdGenerator.new }
    register("stream_factory", memoize: true) { Write::StreamFactory.new }
    register("event_schema_registry", memoize: true) { Write::EventSchemaRegistry.new }
    register("skills.identity_builder", memoize: true) do
      Write::Skills::IdentityBuilder.new(canonical_json: self["canonical_json"])
    end
    register("skills.revision_builder", memoize: true) do
      Write::Skills::RevisionBuilder.new(canonical_json: self["canonical_json"])
    end
    register("skills.persisted_publication_loader", memoize: true) do
      Write::Skills::PersistedPublicationLoader.new(
        schema_registry: self["event_schema_registry"],
        identity_builder: self["skills.identity_builder"],
        revision_builder: self["skills.revision_builder"]
      )
    end
    register("skills.marker_builder", memoize: true) do
      Write::Skills::MarkerBuilder.new(canonical_json: self["canonical_json"])
    end
    register("development_artifacts.content_builder", memoize: true) do
      Write::DevelopmentArtifacts::ContentBuilder.new
    end
    register("development_artifacts.identity_builder", memoize: true) do
      Write::DevelopmentArtifacts::IdentityBuilder.new(canonical_json: self["canonical_json"])
    end
    register("development_artifacts.artifact_builder", memoize: true) do
      Write::DevelopmentArtifacts::ArtifactBuilder.new(
        identity_builder: self["development_artifacts.identity_builder"]
      )
    end
    register("development_artifacts.relation_identity_builder", memoize: true) do
      Write::DevelopmentArtifacts::RelationIdentityBuilder.new(
        canonical_json: self["canonical_json"]
      )
    end
    register("development_artifacts.relation_builder", memoize: true) do
      Write::DevelopmentArtifacts::RelationBuilder.new(
        identity_builder: self["development_artifacts.relation_identity_builder"]
      )
    end
    register("development_artifacts.marker_builder", memoize: true) do
      Write::DevelopmentArtifacts::MarkerBuilder.new
    end
    register("interpretations.topic_registry", memoize: true) do
      Write::Interpretations::TopicRegistry.new
    end
    register("contracts.candidate_impact_policy_proposal", memoize: true) do
      Write::Contracts::CandidateImpactPolicyProposal.new
    end

    register("interpretations.slot_builder", memoize: true) do
      Write::Interpretations::InterpretationSlotBuilder.new(
        topic_registry: self["interpretations.topic_registry"],
        canonical_json: self["canonical_json"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("event_factory", memoize: true) do
      Write::EventFactory.new(registry: self["event_schema_registry"])
    end

    register("command_input_digest", memoize: true) do
      Write::CommandInputDigest.new(canonical_json: self["canonical_json"])
    end

    register("command_completion_builder", memoize: true) do
      Write::CommandCompletionBuilder.new
    end

    register("operations.prepare_register_repository", memoize: true) do
      self["operations.execute_register_repository"].method(:prepare)
    end

    register("operations.prepare_resolve_resource", memoize: true) do
      self["operations.execute_resolve_resource"].method(:prepare)
    end

    register("operations.prepare_remove_resource", memoize: true) do
      self["operations.execute_remove_resource"].method(:prepare)
    end

    register("operations.prepare_create_change_set", memoize: true) do
      Write::Operations::PrepareCreateChangeSet.new
    end

    register("operations.prepare_create_work_item", memoize: true) do
      Write::Operations::PrepareCreateWorkItem.new
    end

    register("operations.prepare_declare_work_item_dependency", memoize: true) do
      Write::Operations::PrepareDeclareWorkItemDependency.new
    end

    register("operations.prepare_activate_change_set", memoize: true) do
      Write::Operations::PrepareActivateChangeSet.new
    end

    register("operations.prepare_acquire_work_item", memoize: true) do
      Write::Operations::PrepareAcquireWorkItem.new
    end

    register("operations.prepare_complete_work_item", memoize: true) do
      Write::Operations::PrepareCompleteWorkItem.new
    end

    register("operations.prepare_abandon_attempt", memoize: true) do
      self["operations.execute_abandon_attempt"].method(:prepare)
    end

    register("operations.prepare_reserve_write_set", memoize: true) do
      Write::Operations::PrepareReserveWriteSet.new
    end

    register("operations.prepare_expand_write_set", memoize: true) do
      Write::Operations::PrepareExpandWriteSet.new
    end

    register("operations.prepare_renew_lease_set", memoize: true) do
      Write::Operations::PrepareRenewLeaseSet.new
    end

    register("operations.prepare_release_lease_set", memoize: true) do
      Write::Operations::PrepareReleaseLeaseSet.new
    end

    register("operations.prepare_record_guidance", memoize: true) do
      Write::Operations::PrepareRecordGuidance.new
    end

    register("operations.prepare_propose_decision_interpretation", memoize: true) do
      Write::Operations::PrepareProposeDecisionInterpretation.new(
        topic_policy_contract: self["contracts.candidate_impact_policy_proposal"]
      )
    end

    register("operations.prepare_adjudicate_decision_interpretation", memoize: true) do
      Write::Operations::PrepareAdjudicateDecisionInterpretation.new
    end

    register("operations.prepare_activate_decision", memoize: true) do
      Write::Operations::PrepareActivateDecision.new
    end

    register("operations.prepare_correct_decision", memoize: true) do
      Write::Operations::PrepareCorrectDecision.new
    end

    register("operations.prepare_record_agent_choice", memoize: true) do
      Write::Operations::PrepareRecordAgentChoice.new
    end

    register("operations.prepare_submit_candidate", memoize: true) do
      Write::Operations::PrepareSubmitCandidate.new
    end

    register("operations.prepare_submit_candidate_impact_surface", memoize: true) do
      Write::Operations::PrepareSubmitCandidateImpactSurface.new
    end

    register("operations.prepare_claim_verification_obligation", memoize: true) do
      Write::Operations::PrepareClaimVerificationObligation.new
    end

    register("operations.prepare_submit_compatibility_assessment", memoize: true) do
      Write::Operations::PrepareSubmitCompatibilityAssessment.new
    end

    register("operations.prepare_waive_verification_obligation", memoize: true) do
      Write::Operations::PrepareWaiveVerificationObligation.new
    end

    register("operations.prepare_register_merge_snapshot", memoize: true) do
      Write::Operations::PrepareRegisterMergeSnapshot.new
    end

    register("operations.prepare_submit_merge_snapshot_verification", memoize: true) do
      Write::Operations::PrepareSubmitMergeSnapshotVerification.new
    end

    register("operations.prepare_request_merge_authorization", memoize: true) do
      Write::Operations::PrepareRequestMergeAuthorization.new
    end

    register("operations.prepare_record_merge_observation", memoize: true) do
      Write::Operations::PrepareRecordMergeObservation.new
    end

    register("operations.prepare_release_set", memoize: true) do
      Write::Operations::PrepareReleaseSet.new
    end

    register("operations.prepare_record_repository_integration", memoize: true) do
      Write::Operations::PrepareRecordRepositoryIntegration.new
    end

    register("operations.prepare_record_release_set_verification", memoize: true) do
      Write::Operations::PrepareRecordReleaseSetVerification.new
    end

    register("operations.prepare_record_release_set_activation", memoize: true) do
      Write::Operations::PrepareRecordReleaseSetActivation.new
    end

    register("operations.prepare_complete_compensated_release_set", memoize: true) do
      Write::Operations::PrepareCompleteCompensatedReleaseSet.new
    end

    register("operations.prepare_publish_skill_revision", memoize: true) do
      Write::Operations::PreparePublishSkillRevision.new(
        identity_builder: self["skills.identity_builder"],
        revision_builder: self["skills.revision_builder"]
      )
    end

    register("operations.prepare_create_skill_publish_batch", memoize: true) do
      Write::Operations::PrepareCreateSkillPublishBatch.new(
        item_preparer: self["operations.prepare_publish_skill_revision"],
        input_digest: self["command_input_digest"]
      )
    end

    register("operations.prepare_capture_development_artifact", memoize: true) do
      Write::Operations::PrepareCaptureDevelopmentArtifact.new(
        content_builder: self["development_artifacts.content_builder"],
        artifact_builder: self["development_artifacts.artifact_builder"]
      )
    end

    register("operations.prepare_correct_development_artifact_classification", memoize: true) do
      Write::Operations::PrepareCorrectDevelopmentArtifactClassification.new
    end

    register("operations.prepare_declare_development_artifact_relation", memoize: true) do
      Write::Operations::PrepareDeclareDevelopmentArtifactRelation.new(
        relation_builder: self["development_artifacts.relation_builder"]
      )
    end

    register("operations.prepare_create_development_artifact_capture_batch", memoize: true) do
      Write::Operations::PrepareCreateDevelopmentArtifactCaptureBatch.new(
        item_preparer: self["operations.prepare_capture_development_artifact"],
        input_digest: self["command_input_digest"]
      )
    end

    register("operations.prepare_create_development_artifact_relation_declare_batch", memoize: true) do
      Write::Operations::PrepareCreateDevelopmentArtifactRelationDeclareBatch.new(
        item_preparer: self["operations.prepare_declare_development_artifact_relation"],
        input_digest: self["command_input_digest"]
      )
    end

    register("operations.prepare_cancel_operation_batch", memoize: true) do
      Write::Operations::PrepareCancelOperationBatch.new
    end

    register("domain.repositories.register", memoize: true) do
      Write::Domain::Repositories::Register.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.create", memoize: true) do
      Write::Domain::ChangeSets::Create.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.create", memoize: true) do
      Write::Domain::WorkItems::Create.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.declare_work_item_dependency", memoize: true) do
      Write::Domain::ChangeSets::DeclareWorkItemDependency.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.activate", memoize: true) do
      Write::Domain::ChangeSets::Activate.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.satisfy_work_item_dependency", memoize: true) do
      Write::Domain::ChangeSets::SatisfyWorkItemDependency.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.complete", memoize: true) do
      Write::Domain::ChangeSets::Complete.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.evaluate_readiness", memoize: true) do
      Write::Domain::WorkItems::EvaluateReadiness.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.acquire", memoize: true) do
      Write::Domain::WorkItems::Acquire.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.complete", memoize: true) do
      Write::Domain::WorkItems::Complete.new(stream_factory: self["stream_factory"])
    end

    register("domain.attempts.abandon", memoize: true) do
      Write::Domain::Attempts::Abandon.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.reserve", memoize: true) do
      Write::Domain::ResourceLeases::Reserve.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.expand", memoize: true) do
      Write::Domain::ResourceLeases::Expand.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.renew", memoize: true) do
      Write::Domain::ResourceLeases::Renew.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.release", memoize: true) do
      Write::Domain::ResourceLeases::Release.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.expire", memoize: true) do
      Write::Domain::ResourceLeases::Expire.new(stream_factory: self["stream_factory"])
    end

    register("domain.verification_obligation_claims.claim", memoize: true) do
      Write::Domain::VerificationObligationClaims::Claim.new(
        stream_factory: self["stream_factory"]
      )
    end

    register("domain.verification_evidence.submit", memoize: true) do
      Write::Domain::VerificationEvidence::Submit.new(
        stream_factory: self["stream_factory"]
      )
    end

    register("domain.verification_obligation_waivers.waive", memoize: true) do
      Write::Domain::VerificationObligationWaivers::Waive.new(
        stream_factory: self["stream_factory"]
      )
    end

    register("domain.guidance.record", memoize: true) do
      Write::Domain::Guidance::Record.new(stream_factory: self["stream_factory"])
    end

    register("domain.interpretations.propose", memoize: true) do
      Write::Domain::Interpretations::Propose.new(
        stream_factory: self["stream_factory"],
        topic_registry: self["interpretations.topic_registry"],
        topic_policy_contract: self["contracts.candidate_impact_policy_proposal"]
      )
    end

    register("domain.interpretations.adjudicate", memoize: true) do
      Write::Domain::Interpretations::Adjudicate.new(stream_factory: self["stream_factory"])
    end

    register("decisions.definition_builder", memoize: true) do
      Write::Decisions::DecisionDefinitionBuilder.new(
        topic_registry: self["interpretations.topic_registry"],
        canonical_json: self["canonical_json"]
      )
    end

    register("decisions.slot_builder", memoize: true) do
      Write::Decisions::DecisionSlotBuilder.new(
        canonical_json: self["canonical_json"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("decisions.partition_builder", memoize: true) do
      Write::Decisions::DecisionPartitionBuilder.new
    end

    register("domain.decisions.activation_eligibility", memoize: true) do
      Write::Domain::Decisions::ActivationEligibility.new(
        topic_registry: self["interpretations.topic_registry"]
      )
    end

    register("domain.decisions.prepare_activation", memoize: true) do
      Write::Domain::Decisions::PrepareActivation.new(
        eligibility: self["domain.decisions.activation_eligibility"],
        definition_builder: self["decisions.definition_builder"],
        slot_builder: self["decisions.slot_builder"],
        partition_builder: self["decisions.partition_builder"]
      )
    end

    register("domain.decisions.activate", memoize: true) do
      Write::Domain::Decisions::Activate.new(stream_factory: self["stream_factory"])
    end

    register("domain.decisions.correction_eligibility", memoize: true) do
      Write::Domain::Decisions::CorrectionEligibility.new(
        topic_registry: self["interpretations.topic_registry"]
      )
    end

    register("domain.decisions.prepare_correction", memoize: true) do
      Write::Domain::Decisions::PrepareCorrection.new(
        eligibility: self["domain.decisions.correction_eligibility"],
        definition_builder: self["decisions.definition_builder"],
        slot_builder: self["decisions.slot_builder"],
        partition_builder: self["decisions.partition_builder"]
      )
    end

    register("domain.decisions.correct", memoize: true) do
      Write::Domain::Decisions::Correct.new(stream_factory: self["stream_factory"])
    end

    register("decision_contexts.partition_selector", memoize: true) do
      Write::DecisionContexts::PartitionSelector.new
    end

    register("decision_contexts.resolver", memoize: true) do
      Write::DecisionContexts::Resolver.new
    end

    register("decision_contexts.builder", memoize: true) do
      Write::DecisionContexts::Builder.new(canonical_json: self["canonical_json"])
    end

    register("domain.agent_choices.record", memoize: true) do
      Write::Domain::AgentChoices::Record.new(stream_factory: self["stream_factory"])
    end

    register("domain.candidates.submit", memoize: true) do
      Write::Domain::Candidates::Submit.new(stream_factory: self["stream_factory"])
    end

    register("domain.skills.publish", memoize: true) do
      Write::Domain::Skills::Publish.new(stream_factory: self["stream_factory"])
    end

    register("domain.development_artifacts.capture", memoize: true) do
      Write::Domain::DevelopmentArtifacts::Capture.new(stream_factory: self["stream_factory"])
    end

    register("domain.development_artifacts.correct_classification", memoize: true) do
      Write::Domain::DevelopmentArtifacts::CorrectClassification.new(
        stream_factory: self["stream_factory"]
      )
    end

    register("domain.development_artifacts.declare_relation", memoize: true) do
      Write::Domain::DevelopmentArtifacts::DeclareRelation.new(
        stream_factory: self["stream_factory"]
      )
    end

    register("domain.candidates.submit_impact_surface", memoize: true) do
      Write::Domain::Candidates::SubmitImpactSurface.new(stream_factory: self["stream_factory"])
    end

    register("merge_snapshots.snapshot_digest_builder", memoize: true) do
      Write::MergeSnapshots::SnapshotDigestBuilder.new(canonical_json: self["canonical_json"])
    end

    register("merge_snapshots.commit_identity_builder", memoize: true) do
      Write::MergeSnapshots::CommitIdentityBuilder.new(
        canonical_json: self["canonical_json"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("merge_snapshots.candidate_loader") do
      Write::MergeSnapshots::CandidateLoader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"]
      )
    end

    register("domain.merge_snapshots.register", memoize: true) do
      Write::Domain::MergeSnapshots::Register.new(
        stream_factory: self["stream_factory"],
        snapshot_digest_builder: self["merge_snapshots.snapshot_digest_builder"]
      )
    end

    register("merge_snapshot_verifications.input_digest", memoize: true) do
      Write::MergeSnapshotVerifications::VerificationInputDigest.new(
        canonical_json: self["canonical_json"]
      )
    end

    register("merge_snapshot_verifications.verified_digest_builder", memoize: true) do
      Write::MergeSnapshotVerifications::VerifiedDigestBuilder.new(
        canonical_json: self["canonical_json"]
      )
    end

    register("domain.merge_snapshot_verifications.submit", memoize: true) do
      Write::Domain::MergeSnapshotVerifications::Submit.new(
        stream_factory: self["stream_factory"],
        verified_digest_builder: self["merge_snapshot_verifications.verified_digest_builder"]
      )
    end

    register("merge_authorizations.evaluator") do
      Write::MergeAuthorizations::Evaluator.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"],
        canonical_json: self["canonical_json"]
      )
    end

    register("merge_authorizations.decision_digest_builder", memoize: true) do
      Write::MergeAuthorizations::DecisionDigestBuilder.new(canonical_json: self["canonical_json"])
    end

    register("domain.merge_authorizations.decide", memoize: true) do
      Write::Domain::MergeAuthorizations::Decide.new
    end

    register("merge_observations.observation_digest_builder", memoize: true) do
      Write::MergeObservations::ObservationDigestBuilder.new(canonical_json: self["canonical_json"])
    end

    register("domain.merge_observations.record", memoize: true) do
      Write::Domain::MergeObservations::Record.new(stream_factory: self["stream_factory"])
    end

    register("release_sets.member_loader") do
      Write::ReleaseSets::MemberLoader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"],
        evaluator: self["merge_authorizations.evaluator"]
      )
    end

    register("release_sets.history_loader", memoize: true) do
      Write::ReleaseSets::HistoryLoader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"]
      )
    end

    register("release_sets.correlation_loader", memoize: true) do
      Write::ReleaseSets::CorrelationLoader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"]
      )
    end

    register("tasks.correlation_resolver", memoize: true) do
      Write::Tasks::CorrelationResolver.new(
        release_set_correlation_loader: self["release_sets.correlation_loader"]
      )
    end

    register("domain.release_sets.prepare", memoize: true) do
      Write::Domain::ReleaseSets::Prepare.new(
        stream_factory: self["stream_factory"],
        digest_builder: Write::ReleaseSets::ReleaseDigestBuilder.new(
          canonical_json: self["canonical_json"]
        )
      )
    end

    register("domain.release_sets.record_repository_integration", memoize: true) do
      Write::Domain::ReleaseSets::RecordRepositoryIntegration.new(
        stream_factory: self["stream_factory"],
        digest_builder: Write::ReleaseSets::IntegrationDigestBuilder.new(
          canonical_json: self["canonical_json"]
        )
      )
    end

    register("domain.release_sets.record_verification", memoize: true) do
      Write::Domain::ReleaseSets::RecordVerification.new(
        stream_factory: self["stream_factory"],
        digest_builder: Write::ReleaseSets::VerificationDigestBuilder.new(
          canonical_json: self["canonical_json"]
        )
      )
    end

    register("domain.release_sets.record_activation", memoize: true) do
      Write::Domain::ReleaseSets::RecordActivation.new(
        stream_factory: self["stream_factory"],
        digest_builder: Write::ReleaseSets::ActivationDigestBuilder.new(
          canonical_json: self["canonical_json"]
        )
      )
    end

    register("domain.release_sets.request_compensation", memoize: true) do
      Write::Domain::ReleaseSets::RequestCompensation.new(stream_factory: self["stream_factory"])
    end

    register("domain.release_sets.complete_activated", memoize: true) do
      Write::Domain::ReleaseSets::CompleteActivated.new(
        stream_factory: self["stream_factory"],
        digest_builder: Write::ReleaseSets::CompletionDigestBuilder.new(
          canonical_json: self["canonical_json"]
        )
      )
    end

    register("domain.release_sets.complete_compensated", memoize: true) do
      Write::Domain::ReleaseSets::CompleteCompensated.new(
        stream_factory: self["stream_factory"],
        digest_builder: Write::ReleaseSets::CompletionDigestBuilder.new(
          canonical_json: self["canonical_json"]
        )
      )
    end

    register("change_set_activation_source_builder", memoize: true) do
      Processes::ChangeSetActivationSourceBuilder.new(schema_registry: self["event_schema_registry"])
    end

    register("lease_expiry_source_builder", memoize: true) do
      Processes::LeaseExpirySourceBuilder.new(
        contract: Processes::Contracts::LeaseExpirySourceEvent.new(
          compound_marker_builder: self["compound_marker_builder"]
        ),
        schema_registry: self["event_schema_registry"]
      )
    end

    register("lease_expiry_command_builder", memoize: true) do
      Processes::LeaseExpiryCommandBuilder.new
    end

    register("readiness_command_builder", memoize: true) do
      Processes::ReadinessCommandBuilder.new(compound_marker_builder: self["compound_marker_builder"])
    end

    register("build_progress.source_builder", memoize: true) do
      Processes::BuildProgress::SourceBuilder.new(schema_registry: self["event_schema_registry"])
    end

    register("build_progress.command_builder", memoize: true) do
      Processes::BuildProgress::CommandBuilder.new(compound_marker_builder: self["compound_marker_builder"])
    end

    register("readiness_targets_builder", memoize: true) { Processes::ReadinessTargetsBuilder.new }

    register("event_store", memoize: true) do
      Write::EventStore.new(client: PgEventstore.client)
    end

    register("dependency_satisfactions.source_loader", memoize: true) do
      Write::DependencySatisfactions::SourceLoader.new(
        event_store: self["event_store"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        release_history_loader: self["release_sets.history_loader"]
      )
    end

    register("change_set_completions.source_loader", memoize: true) do
      Write::ChangeSetCompletions::SourceLoader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"]
      )
    end

    register("change_set_completions.work_item_loader", memoize: true) do
      Write::ChangeSetCompletions::WorkItemLoader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"]
      )
    end

    register("lease_expiry_source_loader", memoize: true) do
      Processes::LeaseExpirySourceLoader.new(
        event_store: self["event_store"],
        source_builder: self["lease_expiry_source_builder"],
        stream_factory: self["stream_factory"]
      )
    end

    register("lease_expiry_job_scheduler", memoize: true) do
      Processes::LeaseExpiryJobScheduler.new
    end

    register("tasks.loader", memoize: true) do
      Write::Tasks::Loader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"]
      )
    end

    register("tasks.target_command_builder", memoize: true) do
      Write::Tasks::TargetCommandBuilder.new
    end

    register("tasks.target_completion_loader", memoize: true) do
      Write::Tasks::TargetCompletionLoader.new(
        event_store: self["event_store"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("tasks.tool_result_mapper", memoize: true) do
      Write::Tasks::ToolResultMapper.new
    end

    register("tasks.semantic_result_mapper", memoize: true) do
      Write::Tasks::SemanticResultMapper.new
    end

    register("repositories.processed_projection_events", memoize: true) do
      Read::Repositories::ProcessedProjectionEvents.new
    end

    register("repositories.command_receipts", memoize: true) do
      Read::Repositories::CommandReceipts.new(schema_registry: self["event_schema_registry"])
    end

    register("repositories.coord_contexts", memoize: true) do
      Read::Repositories::CoordContexts.new
    end

    register("repositories.user_utterances", memoize: true) do
      Read::Repositories::UserUtterances.new
    end

    register("repositories.decision_interpretations", memoize: true) do
      Read::Repositories::DecisionInterpretations.new
    end

    register("repositories.decision_governance", memoize: true) do
      Read::Repositories::DecisionGovernance.new
    end

    register("repositories.agent_choices", memoize: true) do
      Read::Repositories::AgentChoices.new
    end

    register("repositories.agent_choice_impacts", memoize: true) do
      Read::Repositories::AgentChoiceImpacts.new
    end

    register("repositories.candidates", memoize: true) do
      Read::Repositories::Candidates.new
    end

    register("repositories.repository_catalog", memoize: true) do
      Read::Repositories::RepositoryCatalog.new
    end

    register("repositories.resources", memoize: true) do
      Read::Repositories::Resources.new
    end

    register("repositories.skills", memoize: true) do
      Read::Repositories::Skills.new
    end

    register("repositories.development_artifacts", memoize: true) do
      Read::Repositories::DevelopmentArtifacts.new
    end

    register("repositories.operation_batches", memoize: true) do
      Read::Repositories::OperationBatches.new
    end

    register("repositories.candidate_impacts", memoize: true) do
      Read::Repositories::CandidateImpacts.new(
        candidates: self["repositories.candidates"],
        policies: self["repositories.candidate_impact_policies"]
      )
    end

    register("repositories.candidate_impact_policies", memoize: true) do
      Read::Repositories::CandidateImpactPolicies.new
    end

    register("repositories.verification_obligations", memoize: true) do
      Read::Repositories::VerificationObligations.new
    end

    register("repositories.merge_snapshots", memoize: true) do
      Read::Repositories::MergeSnapshots.new(
        authorizations: self["repositories.merge_authorizations"]
      )
    end

    register("repositories.merge_authorizations", memoize: true) do
      Read::Repositories::MergeAuthorizations.new
    end

    register("repositories.release_sets", memoize: true) do
      Read::Repositories::ReleaseSets.new
    end

    register("projectors.coord_context_v1", memoize: true) do
      Read::Projectors::CoordContextV1.new(
        schema_registry: self["event_schema_registry"],
        contexts: self["repositories.coord_contexts"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.command_receipts_v1", memoize: true) do
      Read::Projectors::CommandReceiptsV1.new(
        schema_registry: self["event_schema_registry"],
        receipts: self["repositories.command_receipts"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.user_utterances_v1", memoize: true) do
      Read::Projectors::UserUtterancesV1.new(
        schema_registry: self["event_schema_registry"],
        utterances: self["repositories.user_utterances"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.decision_interpretations_v1", memoize: true) do
      Read::Projectors::DecisionInterpretationsV1.new(
        schema_registry: self["event_schema_registry"],
        interpretations: self["repositories.decision_interpretations"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.decision_governance_v1", memoize: true) do
      Read::Projectors::DecisionGovernanceV1.new(
        schema_registry: self["event_schema_registry"],
        governance: self["repositories.decision_governance"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.agent_choices_v1", memoize: true) do
      Read::Projectors::AgentChoicesV1.new(
        schema_registry: self["event_schema_registry"],
        choices: self["repositories.agent_choices"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.agent_choice_impacts_v1", memoize: true) do
      Read::Projectors::AgentChoiceImpactsV1.new(
        schema_registry: self["event_schema_registry"],
        impacts: self["repositories.agent_choice_impacts"],
        choices: self["repositories.agent_choices"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.candidates_v1", memoize: true) do
      Read::Projectors::CandidatesV1.new(
        schema_registry: self["event_schema_registry"],
        candidates: self["repositories.candidates"],
        candidate_impacts: self["repositories.candidate_impacts"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.repositories_v1", memoize: true) do
      Read::Projectors::RepositoriesV1.new(
        schema_registry: self["event_schema_registry"],
        catalog: self["repositories.repository_catalog"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.resources_v1", memoize: true) do
      Read::Projectors::ResourcesV1.new(
        schema_registry: self["event_schema_registry"],
        resources: self["repositories.resources"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.skills_v1", memoize: true) do
      Read::Projectors::SkillsV1.new(
        publication_loader: self["skills.persisted_publication_loader"],
        identity_builder: self["skills.identity_builder"],
        skills: self["repositories.skills"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.development_artifacts_v1", memoize: true) do
      Read::Projectors::DevelopmentArtifactsV1.new(
        schema_registry: self["event_schema_registry"],
        artifacts: self["repositories.development_artifacts"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.operation_batches_v2", memoize: true) do
      Read::Projectors::OperationBatchesV2.new(
        schema_registry: self["event_schema_registry"],
        batches: self["repositories.operation_batches"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.verification_obligations_v1", memoize: true) do
      Read::Projectors::VerificationObligationsV1.new(
        schema_registry: self["event_schema_registry"],
        obligations: self["repositories.verification_obligations"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.merge_snapshots_v1", memoize: true) do
      Read::Projectors::MergeSnapshotsV1.new(
        schema_registry: self["event_schema_registry"],
        snapshots: self["repositories.merge_snapshots"],
        authorizations: self["repositories.merge_authorizations"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.release_sets_v1", memoize: true) do
      Read::Projectors::ReleaseSetsV1.new(
        schema_registry: self["event_schema_registry"],
        release_sets: self["repositories.release_sets"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("command_completion_lookup", memoize: true) do
      Read::CommandCompletionLookup.new(
        receipts: self["repositories.command_receipts"]
      )
    end

    register("queries.operation_get") do
      Read::Queries::OperationGet.new(
        completions: self["command_completion_lookup"]
      )
    end

    register("queries.coord_context") do
      Read::Queries::CoordContext.new(
        contexts: self["repositories.coord_contexts"],
        canonical_json: self["canonical_json"]
      )
    end

    register("queries.coordination_list") do
      Read::Queries::CoordinationList.new(
        discovery: Read::Repositories::CoordinationDiscovery.new
      )
    end

    register("queries.attempt_list") do
      Read::Queries::CoordContext::AttemptList.new(
        contexts: self["repositories.coord_contexts"]
      )
    end

    register("queries.guidance_get") do
      Read::Queries::GuidanceGet.new(
        utterances: self["repositories.user_utterances"]
      )
    end

    register("queries.decision_interpretation_list") do
      Read::Queries::DecisionInterpretationList.new(
        interpretations: self["repositories.decision_interpretations"]
      )
    end

    register("queries.decision_get") do
      Read::Queries::DecisionGet.new(
        governance: self["repositories.decision_governance"]
      )
    end

    register("queries.decision_list") do
      Read::Queries::DecisionList.new(
        governance: self["repositories.decision_governance"]
      )
    end

    register("queries.decision_resolve") do
      Read::Queries::DecisionResolve.new(
        governance: self["repositories.decision_governance"],
        canonical_json: self["canonical_json"],
        clock: self["clock"]
      )
    end

    register("queries.agent_choice_get") do
      Read::Queries::AgentChoiceGet.new(
        choices: self["repositories.agent_choices"]
      )
    end

    register("queries.agent_choice_impact_list") do
      Read::Queries::AgentChoiceImpactList.new(
        impacts: self["repositories.agent_choice_impacts"]
      )
    end

    register("queries.candidate_get") do
      Read::Queries::CandidateGet.new(candidates: self["repositories.candidates"])
    end

    register("queries.candidate_list") do
      Read::Queries::CandidateList.new(candidates: self["repositories.candidates"])
    end

    register("queries.candidate_impact_get") do
      Read::Queries::CandidateImpactGet.new(impacts: self["repositories.candidate_impacts"])
    end

    register("queries.repository_list") do
      Read::Queries::RepositoryList.new(catalog: self["repositories.repository_catalog"])
    end

    register("queries.resource_get") do
      Read::Queries::ResourceGet.new(resources: self["repositories.resources"])
    end

    register("queries.resource_list") do
      Read::Queries::ResourceList.new(resources: self["repositories.resources"])
    end

    register("queries.skill_get") do
      Read::Queries::SkillGet.new(skills: self["repositories.skills"])
    end

    register("queries.skill_list") do
      Read::Queries::SkillList.new(skills: self["repositories.skills"])
    end

    register("queries.skill_asset_get") do
      Read::Queries::SkillAssetGet.new(skills: self["repositories.skills"])
    end

    register("queries.development_artifact_get") do
      Read::Queries::DevelopmentArtifactGet.new(
        artifacts: self["repositories.development_artifacts"]
      )
    end

    register("queries.development_artifact_content_get") do
      Read::Queries::DevelopmentArtifactContentGet.new(
        artifacts: self["repositories.development_artifacts"]
      )
    end

    register("queries.development_artifact_relation_list") do
      Read::Queries::DevelopmentArtifactRelationList.new(
        artifacts: self["repositories.development_artifacts"]
      )
    end

    register("queries.development_artifact_locator_resolve") do
      Read::Queries::DevelopmentArtifactLocatorResolve.new(
        artifacts: self["repositories.development_artifacts"]
      )
    end

    register("queries.development_artifact_list") do
      Read::Queries::DevelopmentArtifactList.new(
        artifacts: self["repositories.development_artifacts"]
      )
    end

    register("queries.operation_batch_get") do
      Read::Queries::OperationBatchGet.new(batches: self["repositories.operation_batches"])
    end

    register("queries.verification_obligations_list") do
      Read::Queries::VerificationObligationsList.new(
        obligations: self["repositories.verification_obligations"],
        clock: self["clock"]
      )
    end

    register("queries.merge_snapshot_get") do
      Read::Queries::MergeSnapshotGet.new(
        snapshots: self["repositories.merge_snapshots"]
      )
    end

    register("queries.release_set_get") do
      Read::Queries::ReleaseSetGet.new(
        release_sets: self["repositories.release_sets"]
      )
    end

    register("mcp.settings", memoize: true) { Mcp::SettingsLoader.new.call }
    register("mcp.tasks.result_mapper", memoize: true) { Mcp::Tasks::ResultMapper.new }
    register("mcp.tasks.extension", memoize: true) do
      Mcp::Tasks::Extension.new(
        get_task: self["operations.get_coordination_task"],
        acknowledge_task_input: self["operations.acknowledge_task_input"],
        cancel_task: self["operations.cancel_coordination_task"],
        result_mapper: self["mcp.tasks.result_mapper"],
        terminal_result_validator: Mcp::Tasks::TerminalResultValidator.new
      )
    end
    register("mcp.server", memoize: true) do
      Mcp::ServerFactory.new(tasks_extension: self["mcp.tasks.extension"]).call
    end
    register("mcp.transport", memoize: true) do
      Mcp::TransportFactory.new.call(
        server: self["mcp.server"],
        settings: self["mcp.settings"]
      )
    end

    register("operations.execute_register_repository") do
      Write::Operations::ExecuteRegisterRepository.new(
        event_store: self["event_store"],
        decider: self["domain.repositories.register"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("operations.execute_resolve_resource") do
      Write::Operations::ExecuteResolveResource.new(
        event_store: self["event_store"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_remove_resource") do
      Write::Operations::ExecuteRemoveResource.new(
        event_store: self["event_store"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_create_change_set") do
      Write::Operations::ExecuteCreateChangeSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_create_change_set"],
        decider: self["domain.change_sets.create"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("operations.execute_create_work_item") do
      Write::Operations::ExecuteCreateWorkItem.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_create_work_item"],
        decider: self["domain.work_items.create"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("operations.execute_declare_work_item_dependency") do
      Write::Operations::ExecuteDeclareWorkItemDependency.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_declare_work_item_dependency"],
        decider: self["domain.change_sets.declare_work_item_dependency"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_activate_change_set") do
      Write::Operations::ExecuteActivateChangeSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_activate_change_set"],
        decider: self["domain.change_sets.activate"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_evaluate_work_item_readiness") do
      Write::Operations::ExecuteEvaluateWorkItemReadiness.new(
        event_store: self["event_store"],
        decider: self["domain.work_items.evaluate_readiness"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_satisfy_work_item_dependency") do
      Write::Operations::ExecuteSatisfyWorkItemDependency.new(
        event_store: self["event_store"],
        source_loader: self["dependency_satisfactions.source_loader"],
        decider: self["domain.change_sets.satisfy_work_item_dependency"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_complete_change_set") do
      Write::Operations::ExecuteCompleteChangeSet.new(
        event_store: self["event_store"],
        source_loader: self["change_set_completions.source_loader"],
        work_item_loader: self["change_set_completions.work_item_loader"],
        release_history_loader: self["release_sets.history_loader"],
        decider: self["domain.change_sets.complete"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_acquire_work_item") do
      Write::Operations::ExecuteAcquireWorkItem.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_acquire_work_item"],
        decider: self["domain.work_items.acquire"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_complete_work_item") do
      Write::Operations::ExecuteCompleteWorkItem.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_complete_work_item"],
        decider: self["domain.work_items.complete"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_abandon_attempt", memoize: true) do
      Write::Operations::ExecuteAbandonAttempt.new(
        event_store: self["event_store"],
        contract: Write::Contracts::AbandonAttempt.new,
        decider: self["domain.attempts.abandon"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        event_plan_contract: Write::Contracts::AttemptAbandonmentEventPlan.new
      )
    end

    register("operations.execute_reserve_write_set") do
      Write::Operations::ExecuteReserveWriteSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_reserve_write_set"],
        decider: self["domain.resource_leases.reserve"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_expand_write_set") do
      Write::Operations::ExecuteExpandWriteSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_expand_write_set"],
        decider: self["domain.resource_leases.expand"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_renew_lease_set") do
      Write::Operations::ExecuteRenewLeaseSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_renew_lease_set"],
        decider: self["domain.resource_leases.renew"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_release_lease_set") do
      Write::Operations::ExecuteReleaseLeaseSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_release_lease_set"],
        decider: self["domain.resource_leases.release"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_expire_resource_lease") do
      Write::Operations::ExecuteExpireResourceLease.new(
        event_store: self["event_store"],
        decider: self["domain.resource_leases.expire"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_roll_resource_boundary_epoch") do
      Write::Operations::ExecuteRollResourceBoundaryEpoch.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"]
      )
    end

    register("operations.execute_record_guidance") do
      Write::Operations::ExecuteRecordGuidance.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_guidance"],
        decider: self["domain.guidance.record"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_propose_decision_interpretation") do
      Write::Operations::ExecuteProposeDecisionInterpretation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_propose_decision_interpretation"],
        decider: self["domain.interpretations.propose"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_adjudicate_decision_interpretation") do
      Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_adjudicate_decision_interpretation"],
        decider: self["domain.interpretations.adjudicate"],
        slot_builder: self["interpretations.slot_builder"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_activate_decision") do
      Write::Operations::ExecuteActivateDecision.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_activate_decision"],
        candidate_preparer: self["domain.decisions.prepare_activation"],
        decider: self["domain.decisions.activate"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_correct_decision") do
      Write::Operations::ExecuteCorrectDecision.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_correct_decision"],
        candidate_preparer: self["domain.decisions.prepare_correction"],
        decider: self["domain.decisions.correct"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_record_agent_choice") do
      Write::Operations::ExecuteRecordAgentChoice.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_agent_choice"],
        partition_selector: self["decision_contexts.partition_selector"],
        resolver: self["decision_contexts.resolver"],
        context_builder: self["decision_contexts.builder"],
        decider: self["domain.agent_choices.record"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_submit_candidate") do
      Write::Operations::ExecuteSubmitCandidate.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_submit_candidate"],
        decider: self["domain.candidates.submit"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_publish_skill_revision") do
      Write::Operations::ExecutePublishSkillRevision.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_publish_skill_revision"],
        decider: self["domain.skills.publish"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        publication_loader: self["skills.persisted_publication_loader"],
        stream_factory: self["stream_factory"],
        marker_builder: self["skills.marker_builder"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("development_artifacts.loader", memoize: true) do
      Write::DevelopmentArtifacts::Loader.new(
        event_store: self["event_store"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_capture_development_artifact") do
      Write::Operations::ExecuteCaptureDevelopmentArtifact.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_capture_development_artifact"],
        loader: self["development_artifacts.loader"],
        decider: self["domain.development_artifacts.capture"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        marker_builder: self["development_artifacts.marker_builder"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_correct_development_artifact_classification") do
      Write::Operations::ExecuteCorrectDevelopmentArtifactClassification.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_correct_development_artifact_classification"],
        loader: self["development_artifacts.loader"],
        decider: self["domain.development_artifacts.correct_classification"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        marker_builder: self["development_artifacts.marker_builder"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_declare_development_artifact_relation") do
      Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_declare_development_artifact_relation"],
        loader: self["development_artifacts.loader"],
        decider: self["domain.development_artifacts.declare_relation"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        marker_builder: self["development_artifacts.marker_builder"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operation_batches.loader", memoize: true) do
      Write::OperationBatches::Loader.new(
        event_store: self["event_store"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_operation_batch_command", memoize: true) do
      Write::Operations::ExecuteOperationBatchCommand.new(
        event_store: self["event_store"],
        loader: self["operation_batches.loader"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_submit_candidate_impact_surface") do
      Write::Operations::ExecuteSubmitCandidateImpactSurface.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_submit_candidate_impact_surface"],
        decider: self["domain.candidates.submit_impact_surface"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_register_merge_snapshot") do
      Write::Operations::ExecuteRegisterMergeSnapshot.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_register_merge_snapshot"],
        decider: self["domain.merge_snapshots.register"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        commit_identity_builder: self["merge_snapshots.commit_identity_builder"],
        candidate_loader: self["merge_snapshots.candidate_loader"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_submit_merge_snapshot_verification") do
      Write::Operations::ExecuteSubmitMergeSnapshotVerification.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_submit_merge_snapshot_verification"],
        decider: self["domain.merge_snapshot_verifications.submit"],
        input_digest: self["command_input_digest"],
        verification_input_digest: self["merge_snapshot_verifications.input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_request_merge_authorization") do
      Write::Operations::ExecuteRequestMergeAuthorization.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_request_merge_authorization"],
        evaluator: self["merge_authorizations.evaluator"],
        decider: self["domain.merge_authorizations.decide"],
        input_digest: self["command_input_digest"],
        decision_digest_builder: self["merge_authorizations.decision_digest_builder"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_record_merge_observation") do
      Write::Operations::ExecuteRecordMergeObservation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_merge_observation"],
        evaluator: self["merge_authorizations.evaluator"],
        decider: self["domain.merge_observations.record"],
        input_digest: self["command_input_digest"],
        observation_digest_builder: self["merge_observations.observation_digest_builder"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_prepare_release_set") do
      Write::Operations::ExecutePrepareReleaseSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_release_set"],
        member_loader: self["release_sets.member_loader"],
        decider: self["domain.release_sets.prepare"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_record_repository_integration") do
      Write::Operations::ExecuteRecordRepositoryIntegration.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_repository_integration"],
        history_loader: self["release_sets.history_loader"],
        decider: self["domain.release_sets.record_repository_integration"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_record_release_set_verification") do
      Write::Operations::ExecuteRecordReleaseSetVerification.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_release_set_verification"],
        history_loader: self["release_sets.history_loader"],
        decider: self["domain.release_sets.record_verification"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_record_release_set_activation") do
      Write::Operations::ExecuteRecordReleaseSetActivation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_release_set_activation"],
        history_loader: self["release_sets.history_loader"],
        decider: self["domain.release_sets.record_activation"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_request_release_set_compensation") do
      Write::Operations::ExecuteRequestReleaseSetCompensation.new(
        event_store: self["event_store"],
        history_loader: self["release_sets.history_loader"],
        decider: self["domain.release_sets.request_compensation"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_complete_activated_release_set") do
      Write::Operations::ExecuteCompleteActivatedReleaseSet.new(
        event_store: self["event_store"],
        history_loader: self["release_sets.history_loader"],
        decider: self["domain.release_sets.complete_activated"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_complete_compensated_release_set") do
      Write::Operations::ExecuteCompleteCompensatedReleaseSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_complete_compensated_release_set"],
        history_loader: self["release_sets.history_loader"],
        decider: self["domain.release_sets.complete_compensated"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_claim_verification_obligation") do
      Write::Operations::ExecuteClaimVerificationObligation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_claim_verification_obligation"],
        decider: self["domain.verification_obligation_claims.claim"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_submit_compatibility_assessment") do
      Write::Operations::ExecuteSubmitCompatibilityAssessment.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_submit_compatibility_assessment"],
        decider: self["domain.verification_evidence.submit"],
        input_digest: self["command_input_digest"],
        assessment_input_digest: Write::CompatibilityAssessments::AssessmentInputDigest.new(
          canonical_json: self["canonical_json"]
        ),
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("operations.execute_waive_verification_obligation") do
      Write::Operations::ExecuteWaiveVerificationObligation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_waive_verification_obligation"],
        decider: self["domain.verification_obligation_waivers.waive"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_start_agent_choice_impact_scan", memoize: true) do
      Write::Operations::ExecuteStartAgentChoiceImpactScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_progress_agent_choice_impact_scan", memoize: true) do
      Write::Operations::ExecuteProgressAgentChoiceImpactScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_assess_agent_choice_decision_impact", memoize: true) do
      Write::Operations::ExecuteAssessAgentChoiceDecisionImpact.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_start_candidate_impact_registry_sweep", memoize: true) do
      Write::Operations::ExecuteStartCandidateImpactRegistrySweep.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_progress_candidate_impact_registry_sweep", memoize: true) do
      Write::Operations::ExecuteProgressCandidateImpactRegistrySweep.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_start_candidate_impact_pair_scan", memoize: true) do
      Write::Operations::ExecuteStartCandidateImpactPairScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_progress_candidate_impact_pair_scan", memoize: true) do
      Write::Operations::ExecuteProgressCandidateImpactPairScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_create_candidate_compatibility_obligation", memoize: true) do
      Write::Operations::ExecuteCreateCandidateCompatibilityObligation.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_start_verification_obligation_validity_scan", memoize: true) do
      Write::Operations::ExecuteStartVerificationObligationValidityScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_progress_verification_obligation_validity_scan", memoize: true) do
      Write::Operations::ExecuteProgressVerificationObligationValidityScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_invalidate_verification_obligation", memoize: true) do
      Write::Operations::ExecuteInvalidateVerificationObligation.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("lease_expiry_policy", memoize: true) do
      Processes::LeaseExpiryPolicy.new(
        source_loader: self["lease_expiry_source_loader"],
        command_builder: self["lease_expiry_command_builder"],
        operation: self["operations.execute_expire_resource_lease"]
      )
    end

    register("tasks.target_executor", memoize: true) do
      Write::Tasks::TargetExecutor.new(
        event_store: self["event_store"],
        remove_resource: self["operations.execute_remove_resource"],
        create_change_set: self["operations.execute_create_change_set"],
        create_work_item: self["operations.execute_create_work_item"],
        declare_work_item_dependency: self["operations.execute_declare_work_item_dependency"],
        activate_change_set: self["operations.execute_activate_change_set"],
        acquire_work_item: self["operations.execute_acquire_work_item"],
        complete_work_item: self["operations.execute_complete_work_item"],
        reserve_write_set: self["operations.execute_reserve_write_set"],
        expand_write_set: self["operations.execute_expand_write_set"],
        renew_lease_set: self["operations.execute_renew_lease_set"],
        release_lease_set: self["operations.execute_release_lease_set"],
        record_guidance: self["operations.execute_record_guidance"],
        propose_decision_interpretation: self["operations.execute_propose_decision_interpretation"],
        adjudicate_decision_interpretation: self["operations.execute_adjudicate_decision_interpretation"],
        activate_decision: self["operations.execute_activate_decision"],
        correct_decision: self["operations.execute_correct_decision"],
        record_agent_choice: self["operations.execute_record_agent_choice"],
        submit_candidate: self["operations.execute_submit_candidate"],
        submit_candidate_impact_surface:
          self["operations.execute_submit_candidate_impact_surface"],
        claim_verification_obligation:
          self["operations.execute_claim_verification_obligation"],
        submit_compatibility_assessment:
          self["operations.execute_submit_compatibility_assessment"],
        waive_verification_obligation:
          self["operations.execute_waive_verification_obligation"],
        register_merge_snapshot:
          self["operations.execute_register_merge_snapshot"],
        submit_merge_snapshot_verification:
          self["operations.execute_submit_merge_snapshot_verification"],
        request_merge_authorization:
          self["operations.execute_request_merge_authorization"],
        record_merge_observation:
          self["operations.execute_record_merge_observation"],
        prepare_release_set:
          self["operations.execute_prepare_release_set"],
        record_repository_integration:
          self["operations.execute_record_repository_integration"],
        record_release_set_verification:
          self["operations.execute_record_release_set_verification"],
        record_release_set_activation:
          self["operations.execute_record_release_set_activation"],
        complete_compensated_release_set:
          self["operations.execute_complete_compensated_release_set"],
        publish_skill_revision:
          self["operations.execute_publish_skill_revision"],
        capture_development_artifact:
          self["operations.execute_capture_development_artifact"],
        correct_development_artifact_classification:
          self["operations.execute_correct_development_artifact_classification"],
        declare_development_artifact_relation:
          self["operations.execute_declare_development_artifact_relation"],
        operation_batch_command:
          self["operations.execute_operation_batch_command"]
      )
    end

    register("operations.apply_coordination_task_transition", memoize: true) do
      Write::Operations::ApplyCoordinationTaskTransition.new(
        event_store: self["event_store"],
        loader: self["tasks.loader"],
        stream_factory: self["stream_factory"],
        event_factory: self["event_factory"],
        id_generator: self["id_generator"]
      )
    end

    register("operations.submit_coordination_task") do
      Write::Operations::SubmitCoordinationTask.new(
        event_store: self["event_store"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"],
        correlation_resolver: self["tasks.correlation_resolver"]
      )
    end

    register("operations.submit_register_repository_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_register_repository"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_resolve_resource_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_resolve_resource"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_remove_resource_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_remove_resource"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_create_change_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_create_change_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_create_work_item_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_create_work_item"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_declare_work_item_dependency_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_declare_work_item_dependency"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_activate_change_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_activate_change_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_acquire_work_item_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_acquire_work_item"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_complete_work_item_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_complete_work_item"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_abandon_attempt_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_abandon_attempt"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_reserve_write_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_reserve_write_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_expand_write_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_expand_write_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_renew_lease_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_renew_lease_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_release_lease_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_release_lease_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_guidance_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_guidance"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_propose_decision_interpretation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_propose_decision_interpretation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_adjudicate_decision_interpretation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_adjudicate_decision_interpretation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_activate_decision_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_activate_decision"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_correct_decision_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_correct_decision"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_agent_choice_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_agent_choice"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_candidate_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_submit_candidate"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_publish_skill_revision_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_publish_skill_revision"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_create_skill_publish_batch_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_create_skill_publish_batch"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_capture_development_artifact_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_capture_development_artifact"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_correct_development_artifact_classification_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_correct_development_artifact_classification"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_declare_development_artifact_relation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_declare_development_artifact_relation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_create_development_artifact_capture_batch_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_create_development_artifact_capture_batch"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_create_development_artifact_relation_declare_batch_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_create_development_artifact_relation_declare_batch"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_cancel_operation_batch_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_cancel_operation_batch"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_candidate_impact_surface_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_submit_candidate_impact_surface"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_claim_verification_obligation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_claim_verification_obligation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_compatibility_assessment_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_submit_compatibility_assessment"],
        submitter: self["operations.submit_coordination_task"]
      )
    end


    register("operations.submit_waive_verification_obligation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_waive_verification_obligation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_register_merge_snapshot_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_register_merge_snapshot"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_merge_snapshot_verification_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_submit_merge_snapshot_verification"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_request_merge_authorization_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_request_merge_authorization"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_merge_observation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_merge_observation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_prepare_release_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_release_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_repository_integration_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_repository_integration"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_release_set_verification_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_release_set_verification"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_release_set_activation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_release_set_activation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_complete_compensated_release_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_complete_compensated_release_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.start_coordination_task", memoize: true) do
      Write::Operations::StartCoordinationTask.new(
        transition: self["operations.apply_coordination_task_transition"],
        clock: self["clock"]
      )
    end

    register("operations.record_coordination_task_outcome", memoize: true) do
      Write::Operations::RecordCoordinationTaskOutcome.new(
        transition: self["operations.apply_coordination_task_transition"],
        clock: self["clock"]
      )
    end

    register("operations.cancel_coordination_task") do
      Write::Operations::CancelCoordinationTask.new(
        transition: self["operations.apply_coordination_task_transition"],
        clock: self["clock"]
      )
    end

    register("operations.get_coordination_task") do
      Write::Operations::GetCoordinationTask.new(loader: self["tasks.loader"])
    end

    register("operations.acknowledge_task_input") do
      Write::Operations::AcknowledgeTaskInput.new(loader: self["tasks.loader"])
    end

    register("coordination_task_source_builder", memoize: true) do
      Processes::CoordinationTaskSourceBuilder.new(
        schema_registry: self["event_schema_registry"]
      )
    end


    register("process_managers.change_set_readiness", memoize: true) do
      Processes::ProcessManagers::ChangeSetReadiness.new(
        event_store: self["event_store"],
        source_builder: self["change_set_activation_source_builder"],
        targets_builder: self["readiness_targets_builder"],
        command_builder: self["readiness_command_builder"],
        operation: self["operations.execute_evaluate_work_item_readiness"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("process_managers.coordination_task_executor", memoize: true) do
      Processes::ProcessManagers::CoordinationTaskExecutor.new(
        event_store: self["event_store"],
        source_builder: self["coordination_task_source_builder"],
        task_loader: self["tasks.loader"],
        transition: self["operations.apply_coordination_task_transition"],
        start_task: self["operations.start_coordination_task"],
        record_outcome: self["operations.record_coordination_task_outcome"],
        target_command_builder: self["tasks.target_command_builder"],
        target_executor: self["tasks.target_executor"],
        target_completion_loader: self["tasks.target_completion_loader"],
        semantic_result_mapper: self["tasks.semantic_result_mapper"]
      )
    end

    register("operation_batches.source_builder", memoize: true) do
      Processes::OperationBatches::SourceBuilder.new(
        schema_registry: self["event_schema_registry"]
      )
    end

    register("operation_batches.target_completion_loader", memoize: true) do
      Processes::OperationBatches::TargetCompletionLoader.new(
        event_store: self["event_store"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("process_managers.operation_batch_runner", memoize: true) do
      Processes::ProcessManagers::OperationBatchRunner.new(
        event_store: self["event_store"],
        source_builder: self["operation_batches.source_builder"],
        loader: self["operation_batches.loader"],
        target_builder: self["tasks.target_command_builder"],
        target_executor: self["tasks.target_executor"],
        result_mapper: self["tasks.tool_result_mapper"],
        completion_loader: self["operation_batches.target_completion_loader"],
        batch_executor: self["operations.execute_operation_batch_command"]
      )
    end

    register("process_managers.lease_expiry_scheduler", memoize: true) do
      Processes::ProcessManagers::LeaseExpiryScheduler.new(
        source_builder: self["lease_expiry_source_builder"],
        job_scheduler: self["lease_expiry_job_scheduler"]
      )
    end

    register("process_managers.resource_boundary_maintenance", memoize: true) do
      Processes::ProcessManagers::ResourceBoundaryMaintenance.new(
        event_store: self["event_store"],
        schema_registry: self["event_schema_registry"],
        marker_builder: Write::RepositoryMarkerBuilder.new(
          compound_marker_builder: self["compound_marker_builder"]
        ),
        operation: self["operations.execute_roll_resource_boundary_epoch"]
      )
    end

    register("process_managers.agent_choice_decision_impact", memoize: true) do
      Processes::ProcessManagers::AgentChoiceDecisionImpact.new(
        event_store: self["event_store"],
        start_scan: self["operations.execute_start_agent_choice_impact_scan"],
        progress_scan: self["operations.execute_progress_agent_choice_impact_scan"],
        assess_impact: self["operations.execute_assess_agent_choice_decision_impact"]
      )
    end

    register("process_managers.candidate_impact_obligation_policy", memoize: true) do
      Processes::ProcessManagers::CandidateImpactObligationPolicy.new(
        event_store: self["event_store"],
        start_registry_sweep: self["operations.execute_start_candidate_impact_registry_sweep"],
        progress_registry_sweep: self["operations.execute_progress_candidate_impact_registry_sweep"],
        start_pair_scan: self["operations.execute_start_candidate_impact_pair_scan"],
        progress_pair_scan: self["operations.execute_progress_candidate_impact_pair_scan"],
        create_obligation: self["operations.execute_create_candidate_compatibility_obligation"]
      )
    end

    register("process_managers.verification_obligation_validity", memoize: true) do
      Processes::ProcessManagers::VerificationObligationValidity.new(
        event_store: self["event_store"],
        start_scan: self["operations.execute_start_verification_obligation_validity_scan"],
        progress_scan: self["operations.execute_progress_verification_obligation_validity_scan"],
        invalidate: self["operations.execute_invalidate_verification_obligation"]
      )
    end

    register("process_managers.release_set_lifecycle", memoize: true) do
      Processes::ProcessManagers::ReleaseSetLifecycle.new(
        event_store: self["event_store"],
        request_compensation: self["operations.execute_request_release_set_compensation"],
        complete_activated: self["operations.execute_complete_activated_release_set"]
      )
    end

    register("process_managers.build_progress", memoize: true) do
      Processes::ProcessManagers::BuildProgress.new(
        event_store: self["event_store"],
        source_builder: self["build_progress.source_builder"],
        command_builder: self["build_progress.command_builder"],
        satisfy_dependency: self["operations.execute_satisfy_work_item_dependency"],
        complete_change_set: self["operations.execute_complete_change_set"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("subscriptions.change_set_readiness", memoize: true) do
      Processes::Subscriptions::ChangeSetReadiness.new(handler: self["process_managers.change_set_readiness"])
    end

    register("subscriptions.coordination_task_executors", memoize: true) do
      Processes::Subscriptions::CoordinationTaskExecutor::LANE_COUNT.times.map do |lane_index|
        Processes::Subscriptions::CoordinationTaskExecutor.new(
          handler: self["process_managers.coordination_task_executor"],
          lane_index:
        )
      end.freeze
    end

    register("subscriptions.operation_batch_runner", memoize: true) do
      Processes::Subscriptions::OperationBatchRunner.new(
        handler: self["process_managers.operation_batch_runner"]
      )
    end

    register("subscriptions.lease_expiry_scheduler", memoize: true) do
      Processes::Subscriptions::LeaseExpiryScheduler.new(
        handler: self["process_managers.lease_expiry_scheduler"]
      )
    end

    register("subscriptions.resource_boundary_maintenance", memoize: true) do
      Processes::Subscriptions::ResourceBoundaryMaintenance.new(
        handler: self["process_managers.resource_boundary_maintenance"]
      )
    end

    register("subscriptions.agent_choice_decision_impact", memoize: true) do
      Processes::Subscriptions::AgentChoiceDecisionImpact.new(
        handler: self["process_managers.agent_choice_decision_impact"]
      )
    end

    register("subscriptions.candidate_impact_obligation_policy", memoize: true) do
      Processes::Subscriptions::CandidateImpactObligationPolicy.new(
        handler: self["process_managers.candidate_impact_obligation_policy"]
      )
    end

    register("subscriptions.verification_obligation_validity", memoize: true) do
      Processes::Subscriptions::VerificationObligationValidity.new(
        handler: self["process_managers.verification_obligation_validity"]
      )
    end

    register("subscriptions.release_set_lifecycle", memoize: true) do
      Processes::Subscriptions::ReleaseSetLifecycle.new(
        handler: self["process_managers.release_set_lifecycle"]
      )
    end

    register("subscriptions.build_progress", memoize: true) do
      Processes::Subscriptions::BuildProgress.new(
        handler: self["process_managers.build_progress"]
      )
    end

    register("subscriptions.coord_context", memoize: true) do
      Read::Subscriptions::CoordContext.new(handler: self["projectors.coord_context_v1"])
    end

    register("subscriptions.command_receipts", memoize: true) do
      Read::Subscriptions::CommandReceipts.new(handler: self["projectors.command_receipts_v1"])
    end

    register("subscriptions.user_utterances", memoize: true) do
      Read::Subscriptions::UserUtterances.new(handler: self["projectors.user_utterances_v1"])
    end

    register("subscriptions.decision_interpretations", memoize: true) do
      Read::Subscriptions::DecisionInterpretations.new(
        handler: self["projectors.decision_interpretations_v1"]
      )
    end

    register("subscriptions.decision_governance", memoize: true) do
      Read::Subscriptions::DecisionGovernance.new(
        handler: self["projectors.decision_governance_v1"]
      )
    end

    register("subscriptions.agent_choices", memoize: true) do
      Read::Subscriptions::AgentChoices.new(
        handler: self["projectors.agent_choices_v1"]
      )
    end

    register("subscriptions.agent_choice_impacts", memoize: true) do
      Read::Subscriptions::AgentChoiceImpacts.new(
        handler: self["projectors.agent_choice_impacts_v1"]
      )
    end

    register("subscriptions.candidates", memoize: true) do
      Read::Subscriptions::Candidates.new(handler: self["projectors.candidates_v1"])
    end

    register("subscriptions.repositories", memoize: true) do
      Read::Subscriptions::Repositories.new(handler: self["projectors.repositories_v1"])
    end

    register("subscriptions.resources", memoize: true) do
      Read::Subscriptions::Resources.new(handler: self["projectors.resources_v1"])
    end

    register("subscriptions.skills", memoize: true) do
      Read::Subscriptions::Skills.new(handler: self["projectors.skills_v1"])
    end

    register("subscriptions.development_artifacts", memoize: true) do
      Read::Subscriptions::DevelopmentArtifacts.new(
        handler: self["projectors.development_artifacts_v1"]
      )
    end

    register("subscriptions.operation_batches", memoize: true) do
      Read::Subscriptions::OperationBatches.new(handler: self["projectors.operation_batches_v2"])
    end

    register("subscriptions.verification_obligations", memoize: true) do
      Read::Subscriptions::VerificationObligations.new(
        handler: self["projectors.verification_obligations_v1"]
      )
    end

    register("subscriptions.merge_snapshots", memoize: true) do
      Read::Subscriptions::MergeSnapshots.new(
        handler: self["projectors.merge_snapshots_v1"]
      )
    end

    register("subscriptions.release_sets", memoize: true) do
      Read::Subscriptions::ReleaseSets.new(
        handler: self["projectors.release_sets_v1"]
      )
    end

    register("subscription_managers.process_managers", memoize: true) do
      PgEventstore.subscriptions_manager(
        subscription_set: Processes::Subscriptions::ProcessManagerSet::SET_NAME
      )
    end

    register("subscription_registrations.process_managers", memoize: true) do
      [
        self["subscriptions.change_set_readiness"],
        *self["subscriptions.coordination_task_executors"],
        self["subscriptions.operation_batch_runner"],
        self["subscriptions.lease_expiry_scheduler"],
        self["subscriptions.resource_boundary_maintenance"],
        self["subscriptions.agent_choice_decision_impact"],
        self["subscriptions.candidate_impact_obligation_policy"],
        self["subscriptions.verification_obligation_validity"],
        self["subscriptions.release_set_lifecycle"],
        self["subscriptions.build_progress"]
      ].freeze
    end

    register("subscription_set_factories.process_managers", memoize: true) do
      Shared::Subscriptions::SetFactory.new(
        set_class: Processes::Subscriptions::ProcessManagerSet,
        set_name: Processes::Subscriptions::ProcessManagerSet::SET_NAME,
        registrations: self["subscription_registrations.process_managers"]
      )
    end

    register("subscription_sets.process_managers", memoize: true) do
      self["subscription_set_factories.process_managers"].call(
        manager: self["subscription_managers.process_managers"]
      )
    end


    register("subscription_managers.read_models", memoize: true) do
      PgEventstore.subscriptions_manager(
        subscription_set: Read::Subscriptions::ReadModelSet::SET_NAME
      )
    end

    register("subscription_registrations.read_models", memoize: true) do
      [
        self["subscriptions.coord_context"],
        self["subscriptions.command_receipts"],
        self["subscriptions.user_utterances"],
        self["subscriptions.decision_governance"],
        self["subscriptions.decision_interpretations"],
        self["subscriptions.agent_choices"],
        self["subscriptions.agent_choice_impacts"],
        self["subscriptions.candidates"],
        self["subscriptions.repositories"],
        self["subscriptions.resources"],
        self["subscriptions.skills"],
        self["subscriptions.development_artifacts"],
        self["subscriptions.operation_batches"],
        self["subscriptions.verification_obligations"],
        self["subscriptions.merge_snapshots"],
        self["subscriptions.release_sets"]
      ].freeze
    end

    register("subscription_set_factories.read_models", memoize: true) do
      Shared::Subscriptions::SetFactory.new(
        set_class: Read::Subscriptions::ReadModelSet,
        set_name: Read::Subscriptions::ReadModelSet::SET_NAME,
        registrations: self["subscription_registrations.read_models"]
      )
    end

    register("subscription_sets.read_models", memoize: true) do
      self["subscription_set_factories.read_models"].call(
        manager: self["subscription_managers.read_models"]
      )
    end
  end

  Import = Dry::AutoInject(Container)
end
