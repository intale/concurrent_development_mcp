# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelCandidateTransformer
      include Dry::Monads[:result]

      def initialize(context_resolver:, stream_identity_allocator:, compound_marker_builder:)
        @context_resolver = context_resolver
        @stream_identity_allocator = stream_identity_allocator
        @compound_marker_builder = compound_marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        context = @context_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_candidate_id: source_payload.candidate_id
        )
        return context if context.failure?

        transform(
          migration_id:,
          source_config_name:,
          source_event:,
          source: source_payload,
          context: context.value!
        )
      end

      private

      def transform(migration_id:, source_config_name:, source_event:, source:, context:)
        unless source.candidate_id == context.source_candidate_id
          return Failure(inconsistent(source_event, "Candidate identity disagrees with its stream"))
        end

        case source
        when Events::CandidateCreatedV1
          success(context:, source_event:, event: Events::CandidateCreatedV1.new(candidate_id: context.candidate_id),
                  step_name: "create-candidate")
        when Events::CandidateAssignedToAttemptV1
          success(
            context:,
            source_event:,
            event: Events::CandidateAssignedToAttemptV1.new(
              candidate_id: context.candidate_id,
              attempt_id: context.attempt_id,
              work_item_id: context.work_item_id,
              change_set_id: context.change_set_id
            ),
            step_name: "assign-candidate-to-attempt"
          )
        when Events::CandidateAssignedToRepositoryV1
          success(
            context:,
            source_event:,
            event: Events::CandidateAssignedToRepositoryV1.new(
              candidate_id: context.candidate_id,
              repository_id: context.repository_id
            ),
            step_name: "assign-candidate-to-repository"
          )
        when Events::CandidateTargetBranchSelectedV1
          success(
            context:,
            source_event:,
            event: Events::CandidateTargetBranchSelectedV1.new(
              candidate_id: context.candidate_id,
              target_branch: source.target_branch
            ),
            step_name: "select-candidate-target-branch"
          )
        when Events::CandidateCommitRangeDeclaredV1
          success(
            context:,
            source_event:,
            event: Events::CandidateCommitRangeDeclaredV1.new(
              candidate_id: context.candidate_id,
              object_format: source.object_format,
              base_commit_oid: source.base_commit_oid,
              head_commit_oid: source.head_commit_oid
            ),
            step_name: "declare-candidate-commit-range"
          )
        when Events::CandidateCheckpointKindSelectedV1
          success(
            context:,
            source_event:,
            event: Events::CandidateCheckpointKindSelectedV1.new(
              candidate_id: context.candidate_id,
              checkpoint_kind: source.checkpoint_kind
            ),
            step_name: "select-candidate-checkpoint-kind"
          )
        when Events::CandidateWorkIntentionSetAssignedV1
          success(
            context:,
            source_event:,
            event: Events::CandidateWorkIntentionSetAssignedV1.new(
              candidate_id: context.candidate_id,
              intention_set_id: context.intention_set_id
            ),
            step_name: "assign-candidate-work-intention-set"
          )
        when Events::CandidateChangeManifestCapturedV2
          success(
            context:,
            source_event:,
            event: Events::CandidateChangeManifestCapturedV2.new(
              candidate_id: context.candidate_id,
              evidence_revision: source.evidence_revision,
              files: source.files
            ),
            step_name: "capture-candidate-change-manifest",
            metadata_extension: candidate_manifest_metadata(source_event)
          )
        when Events::CandidateSubmittedV3
          success(context:, source_event:, event: Events::CandidateSubmittedV3.new(candidate_id: context.candidate_id),
                  step_name: "submit-candidate")
        when Events::CandidateHeadRegisteredV2
          transform_head(
            migration_id:,
            source_config_name:,
            source_event:,
            source:,
            context:
          )
        end
      end

      def transform_head(migration_id:, source_config_name:, source_event:, source:, context:)
        unless [ source.attempt_id, source.repository_id, source.object_format, source.head_commit_oid ] ==
            [
              context.source_attempt_id,
              context.source_repository_id,
              context.object_format,
              context.head_commit_oid
            ]
          return Failure(inconsistent(source_event, "Candidate head disagrees with Candidate context"))
        end

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "CandidateHead",
          identity_role: "candidate-head"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "candidate-head-identity",
            components: [
              "repository:#{context.repository_id}",
              "object-format:#{source.object_format}",
              "head-commit-oid:#{source.head_commit_oid}"
            ]
          )
        ).marker
        Success([
          TransformedFactV1.new(
            target_stream:,
            event: Events::CandidateHeadRegisteredV2.new(
              registry_id: target_stream.stream_id,
              candidate_id: context.candidate_id,
              attempt_id: context.attempt_id,
              repository_id: context.repository_id,
              object_format: source.object_format,
              head_commit_oid: source.head_commit_oid
            ),
            markers: context.markers + [ marker ],
            step_name: "register-candidate-head",
            metadata_extension: metadata_extension(
              source_event,
              marker_codec_version: source_event.metadata["marker_codec_version"]
            )
          )
        ])
      end

      def success(context:, source_event:, event:, step_name:, metadata_extension: nil)
        Success([
          TransformedFactV1.new(
            target_stream: context.candidate_stream,
            event:,
            markers: context.markers,
            step_name:,
            metadata_extension: metadata_extension || self.metadata_extension(source_event)
          )
        ])
      end

      def candidate_manifest_metadata(source_event)
        collector = source_event.metadata.fetch("collector")
        metadata_extension(
          source_event,
          collector: Candidates::EvidenceCollectorV1.new(
            kind: collector.fetch("kind"),
            id: collector.fetch("id"),
            collector_version: collector.fetch("collector_version")
          ),
          manifest_digest: source_event.metadata.fetch("manifest_digest")
        )
      end

      def metadata_extension(source_event, **attributes)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version: source_event.metadata["policy_version"],
          **attributes
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message:,
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
