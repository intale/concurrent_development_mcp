# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelCommandInputRebinder
      include Dry::Monads[:result]

      TARGETS = {
        repository: [ "DevelopmentPlanning", "Repository", "repository" ],
        change_set: [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        work_item: [ "DevelopmentExecution", "WorkItem", "work-item" ],
        attempt: [ "DevelopmentExecution", "Attempt", "attempt" ],
        candidate: [ "DevelopmentIntegration", "Candidate", "candidate" ],
        resource: [ "DevelopmentCoordination", "Resource", "resource" ],
        work_intention_set: [ "DevelopmentCoordination", "WorkIntentionSet", "work-intention-set" ],
        resource_work_intention: [
          "DevelopmentCoordination", "ResourceWorkIntention", "work-intention"
        ],
        development_artifact: [
          "DevelopmentMemory", "DevelopmentArtifact", "development-artifact"
        ],
        development_artifact_observation: [
          "DevelopmentMemory", "DevelopmentArtifactObservation", "development-artifact-observation"
        ],
        decision: [ "HumanGuidance", "Decision", "decision" ],
        conversation: [ "HumanGuidance", "Conversation", "conversation" ],
        interpretation: [ "HumanGuidance", "Interpretation", "interpretation" ],
        skill: [ "AgentKnowledge", "Skill", "skill" ],
        operation_batch: [ "DevelopmentCoordination", "OperationBatch", "operation-batch" ]
      }.freeze
      RELATION_TARGETS = {
        "artifact" => :development_artifact,
        "change_set" => :change_set,
        "work_item" => :work_item,
        "attempt" => :attempt,
        "candidate" => :candidate,
        "decision" => :decision,
        "skill" => :skill,
        "repository" => :repository,
        "resource" => :resource,
        "operation_batch" => :operation_batch
      }.freeze

      class ResolutionFailure < StandardError
        attr_reader :failure

        def initialize(failure)
          @failure = failure
          super(failure.message)
        end
      end

      def initialize(
        entity_reference_resolver:,
        relation_identity_resolver:,
        legacy_work_intention_context_resolver:,
        guidance_identity_resolver:,
        stream_identity_allocator:,
        event_store:,
        decision_document_transformer:,
        command_input_loader: LegacyCommandInputLoader.new,
        target_command_builder: Tasks::TargetCommandBuilder.new,
        input_digest: CommandInputDigest.new
      )
        @entity_reference_resolver = entity_reference_resolver
        @relation_identity_resolver = relation_identity_resolver
        @legacy_work_intention_context_resolver = legacy_work_intention_context_resolver
        @guidance_identity_resolver = guidance_identity_resolver
        @stream_identity_allocator = stream_identity_allocator
        @event_store = event_store
        @decision_document_transformer = decision_document_transformer
        @command_input_loader = command_input_loader
        @target_command_builder = target_command_builder
        @input_digest = input_digest
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        document:,
        command_id:
      )
        context = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        Success(migrate(document, command_id:, context:))
      rescue ResolutionFailure => error
        Failure(error.failure)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded => error
        Failure(invalid(source_event, document:, error:))
      end

      private

      def migrate(document, command_id:, context:)
        source = @command_input_loader.call(document)
        context = context.merge(
          source_command_id: context.fetch(:source_event).data["command_id"] || source.command_id
        )
        rebound = rebind(source, command_id:, context:)
        command = @target_command_builder.call(rebound)
        MigratedCommandInputV1.new(
          document: rebound,
          canonical_input_digest: @input_digest.request(command)
        )
      end

      def rebind(document, command_id:, context:)
        case document
        when CommandInputDocuments::RegisterRepositoryV1
          repository_register(document, command_id:, context:)
        when CommandInputDocuments::ResolveResourceV1
          resource_resolve(document, command_id:, context:)
        when CommandInputDocuments::CreateChangeSetV1
          change_set_create(document, command_id:, context:)
        when CommandInputDocuments::CreateWorkItemV1
          work_item_create(document, command_id:, context:)
        when CommandInputDocuments::DeclareWorkItemDependencyV1
          work_item_dependency_declare(document, command_id:, context:)
        when CommandInputDocuments::ActivateChangeSetV1
          change_set_activate(document, command_id:, context:)
        when CommandInputDocuments::AcquireWorkItemV1
          work_item_acquire(document, command_id:, context:)
        when CommandInputDocuments::CompleteWorkItemV1
          work_item_complete(document, command_id:, context:)
        when CommandInputDocuments::AbandonAttemptV1
          attempt_abandon(document, command_id:, context:)
        when CommandInputDocuments::ReserveWriteSetV1
          work_intention_set_declare(document, command_id:, context:)
        when CommandInputDocuments::ExpandWriteSetV1
          work_intention_set_expand(document, command_id:, context:)
        when CommandInputDocuments::RenewLeaseSetV1
          work_intention_set_renew(document, command_id:, context:)
        when CommandInputDocuments::ReleaseLeaseSetV1
          work_intention_set_withdraw(document, command_id:, context:)
        when CommandInputDocuments::RecordGuidanceV1
          guidance_record(document, command_id:, context:)
        when LegacyCommandInputDocuments::RecordGuidanceV1
          legacy_guidance_record(document, command_id:, context:)
        when CommandInputDocuments::ProposeDecisionInterpretationV1
          decision_interpretation_propose(document, command_id:, context:)
        when CommandInputDocuments::SubmitCandidateV1
          candidate_submit(document, command_id:, context:)
        when CommandInputDocuments::CaptureDevelopmentArtifactV2
          development_artifact_capture(document, command_id:, context:)
        when LegacyCommandInputDocuments::CaptureDevelopmentArtifactV2
          development_artifact_capture(document, command_id:, context:)
        when CommandInputDocuments::UpdateDevelopmentArtifactV1
          development_artifact_update(document, command_id:, context:)
        when CommandInputDocuments::DeclareDevelopmentArtifactRelationV1
          development_artifact_relation_declare(document, command_id:, context:)
        when LegacyCommandInputDocuments::DeclareDevelopmentArtifactRelationV1
          development_artifact_relation_declare(document, command_id:, context:)
        when LegacyCommandInputDocuments::PublishSkillRevisionV2,
             CommandInputDocuments::PublishSkillRevisionV2
          skill_publish(document, command_id:, context:)
        when CommandInputDocuments::CreateOperationBatchV1
          target(document, command_id:, input: document.input)
        when PostRemodelCommandInputDocuments::LegacyReserveWriteSetV1
          legacy_work_intention_set_declare(document, command_id:, context:)
        when PostRemodelCommandInputDocuments::LegacyExpandWriteSetV1
          legacy_work_intention_set_expand(document, command_id:, context:)
        when PostRemodelCommandInputDocuments::LegacyRenewLeaseSetV1
          legacy_work_intention_set_renew(document, command_id:, context:)
        when PostRemodelCommandInputDocuments::LegacyReleaseLeaseSetV1
          legacy_work_intention_set_withdraw(document, command_id:, context:)
        when PostRemodelCommandInputDocuments::LegacySubmitCandidateV1
          legacy_candidate_submit(document, command_id:, context:)
        else
          raise ArgumentError, "unsupported post-remodel command input #{document.class.name}"
        end
      end

      def repository_register(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::RegisterRepositoryInputV1.new(
          source.to_h.merge(repository_id: resolve(:repository, source.repository_id, context:))
        )
        target(document, command_id:, input:)
      end

      def resource_resolve(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::ResolveResourceInputV1.new(
          actor: source.actor,
          repository_id: resolve(:repository, source.repository_id, context:),
          kind: source.kind,
          path: source.path
        )
        CommandInputDocuments::ResolveResourceV1.new(
          schema: document.schema,
          command_id:,
          tool_name: document.tool_name,
          input:
        )
      end

      def change_set_create(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::CreateChangeSetInputV1.new(
          source.to_h.merge(change_set_id: resolve(:change_set, source.change_set_id, context:))
        )
        target(document, command_id:, input:)
      end

      def work_item_create(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::CreateWorkItemInputV1.new(
          source.to_h.merge(
            change_set_id: resolve(:change_set, source.change_set_id, context:),
            work_item_id: resolve(:work_item, source.work_item_id, context:),
            repository_id: resolve(:repository, source.repository_id, context:)
          )
        )
        target(document, command_id:, input:)
      end

      def work_item_dependency_declare(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::DeclareWorkItemDependencyInputV1.new(
          source.to_h.merge(
            change_set_id: resolve(:change_set, source.change_set_id, context:),
            dependency_id: migrated_dependency_id(source.dependency_id, context:),
            producer_work_item_id: resolve(:work_item, source.producer_work_item_id, context:),
            consumer_work_item_id: resolve(:work_item, source.consumer_work_item_id, context:)
          )
        )
        target(document, command_id:, input:)
      end

      def change_set_activate(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::ActivateChangeSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:)
        )
        target(document, command_id:, input:)
      end

      def work_item_acquire(document, command_id:, context:)
        source = document.input
        snapshots = source.base_snapshots.map do |snapshot|
          CommandInputDocuments::RepositorySnapshotV1.new(
            repository_id: resolve(:repository, snapshot.repository_id, context:),
            object_format: snapshot.object_format,
            commit_oid: snapshot.commit_oid
          )
        end
        input = CommandInputDocuments::AcquireWorkItemInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          base_snapshots: snapshots
        )
        target(document, command_id:, input:)
      end

      def work_item_complete(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::CompleteWorkItemInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          candidate_id: resolve_completion_candidate(document, context:),
          produced_outputs: source.produced_outputs
        )
        target(document, command_id:, input:)
      end

      def attempt_abandon(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::AbandonAttemptInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          reason: source.reason
        )
        target(document, command_id:, input:)
      end

      def work_intention_set_declare(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::ReserveWriteSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          repository_id: resolve(:repository, source.repository_id, context:),
          base_commit_oid: source.base_commit_oid,
          resources: rebind_resources(source.resources, context:),
          ttl_seconds: source.ttl_seconds
        )
        target(document, command_id:, input:)
      end

      def work_intention_set_expand(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::ExpandWriteSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          intention_set_id: resolve(:work_intention_set, source.intention_set_id, context:),
          repository_id: resolve(:repository, source.repository_id, context:),
          base_commit_oid: source.base_commit_oid,
          resources: rebind_resources(source.resources, context:)
        )
        target(document, command_id:, input:)
      end

      def work_intention_set_renew(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::RenewLeaseSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          intention_set_id: resolve(:work_intention_set, source.intention_set_id, context:),
          intentions: rebind_intentions(source.intentions, context:, reference_class: :renew),
          ttl_seconds: source.ttl_seconds
        )
        target(document, command_id:, input:)
      end

      def work_intention_set_withdraw(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::ReleaseLeaseSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          intention_set_id: resolve(:work_intention_set, source.intention_set_id, context:),
          intentions: rebind_intentions(source.intentions, context:, reference_class: :release)
        )
        target(document, command_id:, input:)
      end

      def guidance_record(document, command_id:, context:)
        source = document.input
        guidance = unwrap(
          @guidance_identity_resolver.call(
            **migration_context(context),
            source_conversation_id: source.conversation_id,
            source_message_id: source.message_id
          )
        )
        anchors = source.anchors
        target_anchors = CommandInputDocuments::GuidanceAnchorsV1.new(
          repository_ids: anchors.repository_ids.map { resolve(:repository, _1, context:) },
          change_set_id: optional_resolve(:change_set, anchors.change_set_id, context:),
          work_item_id: optional_resolve(:work_item, anchors.work_item_id, context:),
          attempt_id: optional_resolve(:attempt, anchors.attempt_id, context:)
        )
        input = CommandInputDocuments::RecordGuidanceInputV1.new(
          actor: source.actor,
          message_id: guidance.message_id,
          conversation_id: guidance.target_stream.stream_id,
          source: source.source,
          text: source.text,
          anchors: target_anchors
        )
        target(document, command_id:, input:)
      end

      def legacy_guidance_record(document, command_id:, context:)
        source = document.input
        source_message = legacy_message_event(
          source.message_id,
          source_conversation_id: source.conversation_id,
          context:
        )
        anchors = source.anchors
        input = CommandInputDocuments::RecordGuidanceInputV1.new(
          actor: source.actor,
          message_id: source_message.id,
          conversation_id: resolve(:conversation, source.conversation_id, context:),
          source: source.source,
          text: source.text,
          anchors: CommandInputDocuments::GuidanceAnchorsV1.new(
            repository_ids: anchors.repository_ids.map { resolve(:repository, _1, context:) },
            change_set_id: optional_resolve(:change_set, anchors.change_set_id, context:),
            work_item_id: optional_resolve(:work_item, anchors.work_item_id, context:),
            attempt_id: optional_resolve(:attempt, anchors.attempt_id, context:)
          )
        )
        legacy_target(
          document,
          command_id:,
          tool_name: document.tool_name,
          input:,
          target_class: CommandInputDocuments::RecordGuidanceV1
        )
      end

      def decision_interpretation_propose(document, command_id:, context:)
        source = document.input
        transformed = unwrap(
          @decision_document_transformer.proposed_decision(
            migration_id: context.fetch(:migration_id),
            source_config_name: context.fetch(:source_config_name),
            source_upper_position: context.fetch(:source_upper_position),
            source_event: context.fetch(:source_event),
            proposed_decision: source.proposed_decision
          )
        )
        input = CommandInputDocuments::ProposeDecisionInterpretationInputV1.new(
          source.to_h.merge(
            interpretation_id: resolve(:interpretation, source.interpretation_id, context:),
            source_message_id: legacy_message_event(source.source_message_id, context:).id,
            proposed_decision: Interpretations::SubmittedDecisionV1.new(transformed.to_h)
          )
        )
        target(document, command_id:, input:)
      end

      def candidate_submit(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::SubmitCandidateInputV1.new(
          **candidate_attributes(source, context:),
          intention_set_id: resolve(:work_intention_set, source.intention_set_id, context:),
          intentions: rebind_intentions(source.intentions, context:, reference_class: :candidate)
        )
        target(document, command_id:, input:)
      end

      def development_artifact_capture(document, command_id:, context:)
        source = document.input
        artifact = source.artifact
        target_artifact = CommandInputDocuments::DevelopmentArtifactV2.new(
          artifact_id: resolve_capture_identity(
            :development_artifact,
            artifact.artifact_id,
            context:
          ),
          observation_id: resolve_capture_identity(
            :development_artifact_observation,
            artifact.observation_id,
            context:
          ),
          scope: artifact.scope,
          title: artifact.title,
          kind: artifact.kind,
          labels: artifact.labels,
          content: artifact.content,
          source: artifact.source
        )
        input = CommandInputDocuments::CaptureDevelopmentArtifactInputV2.new(
          actor: source.actor,
          artifact: target_artifact
        )
        CommandInputDocuments::CaptureDevelopmentArtifactV2.new(
          schema: document.schema,
          command_id:,
          tool_name: document.tool_name,
          input:
        )
      end

      def resolve_capture_identity(kind, source_id, context:)
        resolved_id = resolve(kind, source_id, context:)
        return resolved_id if Types::UUID_V7_PATTERN.match?(resolved_id)

        target = TARGETS.fetch(kind)
        allocation = @stream_identity_allocator.call(
          migration_id: context.fetch(:migration_id),
          source_config_name: context.fetch(:source_config_name),
          source_event: context.fetch(:source_event),
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: "unresolved-command-input-#{target.fetch(2)}"
        )
        unwrap(allocation).target_stream.stream_id
      end

      def development_artifact_update(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::UpdateDevelopmentArtifactInputV1.new(
          source.to_h.merge(
            artifact_id: resolve(:development_artifact, source.artifact_id, context:)
          )
        )
        target(document, command_id:, input:)
      end

      def development_artifact_relation_declare(document, command_id:, context:)
        source = document.input
        relation = source.artifact_relation
        target_relation = CommandInputDocuments::DevelopmentArtifactRelationV1.new(
          relation_id: resolve_relation(
            relation.relation_id,
            source_artifact_id: relation.source_artifact_id,
            context:
          ),
          source_artifact_id: resolve(
            :development_artifact,
            relation.source_artifact_id,
            context:
          ),
          relation: relation.relation,
          target: relation_target(relation.target, context:),
          attributes: relation.relation_attributes
        )
        input = CommandInputDocuments::DeclareDevelopmentArtifactRelationInputV1.new(
          actor: source.actor,
          artifact_relation: target_relation,
          supersedes_relation_id: optional_resolve_relation(
            source.supersedes_relation_id,
            source_artifact_id: relation.source_artifact_id,
            context:
          ),
          supersession_reason: source.supersession_reason
        )
        CommandInputDocuments::DeclareDevelopmentArtifactRelationV1.new(
          schema: document.schema,
          command_id:,
          tool_name: document.tool_name,
          input:
        )
      end

      def skill_publish(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::PublishSkillRevisionInputV2.new(
          source.to_h.merge(skill_id: resolve(:skill, source.skill_id, context:))
        )
        CommandInputDocuments::PublishSkillRevisionV2.new(
          schema: document.schema,
          command_id:,
          tool_name: document.tool_name,
          input:
        )
      end

      def legacy_work_intention_set_declare(document, command_id:, context:)
        source = document.input
        input = CommandInputDocuments::ReserveWriteSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          repository_id: resolve(:repository, source.repository_id, context:),
          base_commit_oid: source.base_commit_oid,
          resources: rebind_resources(source.resources, context:),
          ttl_seconds: source.lease_duration_seconds
        )
        legacy_target(document, command_id:, tool_name: "work_intention_set_declare", input:,
                      target_class: CommandInputDocuments::ReserveWriteSetV1)
      end

      def legacy_work_intention_set_expand(document, command_id:, context:)
        source = document.input
        legacy = legacy_work_intention_context(source, context:)
        input = CommandInputDocuments::ExpandWriteSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          intention_set_id: legacy.set_id,
          repository_id: resolve(:repository, source.repository_id, context:),
          base_commit_oid: source.base_commit_oid,
          resources: rebind_resources(source.resources, context:)
        )
        legacy_target(document, command_id:, tool_name: "work_intention_set_expand", input:,
                      target_class: CommandInputDocuments::ExpandWriteSetV1)
      end

      def legacy_work_intention_set_renew(document, command_id:, context:)
        source = document.input
        legacy = legacy_work_intention_context(source, context:)
        input = CommandInputDocuments::RenewLeaseSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          intention_set_id: legacy.set_id,
          intentions: legacy_references(
            source.leases,
            legacy:,
            context:,
            reference_class: :renew
          ),
          ttl_seconds: source.lease_duration_seconds
        )
        legacy_target(document, command_id:, tool_name: "work_intention_set_renew", input:,
                      target_class: CommandInputDocuments::RenewLeaseSetV1)
      end

      def legacy_work_intention_set_withdraw(document, command_id:, context:)
        source = document.input
        legacy = legacy_work_intention_context(source, context:)
        input = CommandInputDocuments::ReleaseLeaseSetInputV1.new(
          actor: source.actor,
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          intention_set_id: legacy.set_id,
          intentions: legacy_references(
            source.leases,
            legacy:,
            context:,
            reference_class: :release
          )
        )
        legacy_target(document, command_id:, tool_name: "work_intention_set_withdraw", input:,
                      target_class: CommandInputDocuments::ReleaseLeaseSetV1)
      end

      def legacy_candidate_submit(document, command_id:, context:)
        source = document.input
        legacy = legacy_work_intention_context(source, context:)
        input = CommandInputDocuments::SubmitCandidateInputV1.new(
          **candidate_attributes(source, context:),
          intention_set_id: legacy.set_id,
          intentions: legacy_references(
            source.leases,
            legacy:,
            context:,
            reference_class: :candidate
          )
        )
        legacy_target(document, command_id:, tool_name: document.tool_name, input:,
                      target_class: CommandInputDocuments::SubmitCandidateV1)
      end

      def target(document, command_id:, input:)
        document.class.new(
          schema: document.schema,
          command_id:,
          tool_name: document.tool_name,
          input:
        )
      end

      def legacy_target(document, command_id:, tool_name:, input:, target_class:)
        target_class.new(schema: document.schema, command_id:, tool_name:, input:)
      end

      def candidate_attributes(source, context:)
        {
          actor: source.actor,
          candidate_id: resolve(:candidate, source.candidate_id, context:),
          change_set_id: resolve(:change_set, source.change_set_id, context:),
          work_item_id: resolve(:work_item, source.work_item_id, context:),
          attempt_id: resolve(:attempt, source.attempt_id, context:),
          repository_id: resolve(:repository, source.repository_id, context:),
          target_branch: source.target_branch,
          object_format: source.object_format,
          base_commit_oid: source.base_commit_oid,
          head_commit_oid: source.head_commit_oid,
          checkpoint_kind: source.checkpoint_kind,
          change_manifest: source.change_manifest,
          build_context: source.build_context,
          actual_resources: source.actual_resources
        }
      end

      def rebind_resources(resources, context:)
        resources.map do |resource|
          CommandInputDocuments::ResourceLeaseTargetV1.new(
            resource_id: resolve(:resource, resource.resource_id, context:),
            base_blob_oid: resource.base_blob_oid,
            mode: resource.mode || "exclusive",
            purpose: resource.purpose || "Preserve legacy exclusive lease semantics",
            context: resource.context
          )
        end
      end

      def rebind_intentions(intentions, context:, reference_class:)
        intentions.map do |reference|
          intention_reference(
            resource_id: resolve(:resource, reference.resource_id, context:),
            intention_id: resolve(
              :resource_work_intention,
              reference.intention_id,
              context:
            ),
            fencing_token: reference.fencing_token,
            reference_class:
          )
        end
      end

      def legacy_references(references, legacy:, context:, reference_class:)
        references.map do |reference|
          resource_id = resolve(:resource, reference.resource_id, context:)
          member = legacy.members.find do |candidate|
            candidate.source_lease_id == reference.lease_id
          end
          unless member && member.resource_id == resource_id
            raise ArgumentError, "legacy work-intention reference cannot be mapped"
          end

          intention_reference(
            resource_id:,
            intention_id: member.intention_id,
            fencing_token: reference.fencing_token,
            reference_class:
          )
        end
      end

      def intention_reference(resource_id:, intention_id:, fencing_token:, reference_class:)
        klass = case reference_class
        when :renew then CommandInputDocuments::LeaseRenewalReferenceV1
        when :release then CommandInputDocuments::LeaseReleaseReferenceV1
        when :candidate then CommandInputDocuments::CandidateLeaseObservationV1
        else raise KeyError, reference_class
        end
        klass.new(resource_id:, intention_id:, fencing_token:)
      end

      def legacy_work_intention_context(source, context:)
        result = @legacy_work_intention_context_resolver.call(
          **migration_context(context),
          attempt_id: source.attempt_id,
          lease_set_id: source.lease_set_id
        )
        unwrap(result)
      end

      def relation_target(source, context:)
        id = if source.kind == "external" || !RELATION_TARGETS.key?(source.kind)
          source.id
        else
          resolve(RELATION_TARGETS.fetch(source.kind), source.id, context:)
        end
        CommandInputDocuments::DevelopmentArtifactRelationTargetV1.new(kind: source.kind, id:)
      end

      def migrated_dependency_id(source_dependency_id, context:)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentExecution",
            stream_name: "WorkItem",
            event_types: [ "WorkItemDependencyDeclared" ],
            markers: [ "dependency:#{source_dependency_id}" ],
            maximum_count: 1,
            direction: :asc,
            to_position: context.fetch(:source_upper_position)
          )
        )
        events.first&.id || source_dependency_id
      end

      def legacy_message_event(source_message_id, context:, source_conversation_id: nil)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "HumanGuidance",
            stream_name: "Conversation",
            event_types: [ "UserUtteranceRecorded", "UserUtteranceForwardedByAgent" ],
            markers: [ "message:#{source_message_id}" ],
            maximum_count: 2,
            direction: :asc,
            to_position: context.fetch(:source_upper_position)
          )
        )
        event = events.one? ? events.first : nil
        data = event&.data
        valid = event && event.metadata["schema_version"] == 1 &&
          data["message_id"] == source_message_id &&
          (!source_conversation_id || data["conversation_id"] == source_conversation_id)
        raise ArgumentError, "legacy guidance message is absent or ambiguous" unless valid

        event
      end

      def resolve(kind, source_id, context:)
        target = TARGETS.fetch(kind)
        source_stream = StreamReference.new(
          context: target.fetch(0),
          stream_name: target.fetch(1),
          stream_id: source_id
        )
        source_event = @event_store.read_at(source_stream, 0)
        unless source_event && source_event.global_position <= context.fetch(:source_upper_position)
          return source_id unless source_command_succeeded?(context.fetch(:source_command_id), context:)
        end

        result = @entity_reference_resolver.call(
          **migration_context(context),
          source_stream:,
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: target.fetch(2)
        )
        unwrap(result).target_stream.stream_id
      end

      def optional_resolve(kind, source_id, context:)
        source_id && resolve(kind, source_id, context:)
      end

      def optional_resolve_relation(source_id, source_artifact_id:, context:)
        source_id && resolve_relation(source_id, source_artifact_id:, context:)
      end

      def resolve_relation(source_relation_id, source_artifact_id:, context:)
        result = @relation_identity_resolver.call(
          **migration_context(context),
          source_relation_id:,
          source_artifact_id:
        )
        if result.failure? && !source_command_succeeded?(context.fetch(:source_command_id), context:)
          return source_relation_id
        end

        unwrap(result).target_stream.stream_id
      end

      def migration_context(context)
        {
          migration_id: context.fetch(:migration_id),
          source_config_name: context.fetch(:source_config_name),
          source_upper_position: context.fetch(:source_upper_position),
          source_event: context.fetch(:source_event)
        }
      end

      def resolve_completion_candidate(document, context:)
        source_id = document.input.candidate_id
        source_stream = StreamReference.new(
          context: "DevelopmentIntegration",
          stream_name: "Candidate",
          stream_id: source_id
        )
        event = @event_store.read_at(source_stream, 0)
        if event && event.global_position <= context.fetch(:source_upper_position)
          return resolve(:candidate, source_id, context:)
        end
        if source_command_succeeded?(context.fetch(:source_command_id), context:)
          raise ArgumentError, "successful work-item completion references an absent candidate"
        end

        source_id
      end

      def source_command_succeeded?(source_command_id, context:)
        return true if source_task_succeeded?(context:)

        source_correlation_id = context.fetch(:source_event).correlation_id
        events = @event_store.read(
          StreamReference.new(
            context: "CoordinatorControl",
            stream_name: "Command",
            stream_id: source_command_id
          ),
          EventReadCriteria.new(
            event_types: %w[CommandCompleted CommandSucceeded],
            maximum_count: 2,
            direction: :asc
          )
        )
        events.any? do |event|
          event.global_position <= context.fetch(:source_upper_position) &&
            event.correlation_id == source_correlation_id &&
            (event.type == "CommandSucceeded" || event.data["status"] == "ok")
        end
      end

      def source_task_succeeded?(context:)
        source_event = context.fetch(:source_event)
        return false unless source_event.stream.context == "CoordinatorControl" &&
          source_event.stream.stream_name == "CoordinationTask"

        events = @event_store.read(
          StreamReference.new(
            context: source_event.stream.context,
            stream_name: source_event.stream.stream_name,
            stream_id: source_event.stream.stream_id
          ),
          EventReadCriteria.new(
            event_types: [ "CoordinationTaskCompleted" ],
            maximum_count: 1,
            direction: :asc
          )
        )
        events.any? do |event|
          result = event.data["result"]
          event.global_position <= context.fetch(:source_upper_position) &&
            event.correlation_id == source_event.correlation_id &&
            result.is_a?(Hash) &&
            (result["kind"] == "success" || result["status"] == "ok")
        end
      end

      def unwrap(result)
        raise ResolutionFailure, result.failure if result.failure?

        result.value!
      end

      def invalid(source_event, document:, error:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel command input #{document.class.name} is invalid: #{error.message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
