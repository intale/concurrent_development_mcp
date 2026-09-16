# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateSubmissionV1Transformer
      include Dry::Monads[:result]

      def initialize(context_resolver:)
        @context_resolver = context_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when Events::CandidateSubmittedV2
          submitted_facts(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::CandidateAttachedToAttemptV1
          coalesce_attempt_assignment(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        end
      end

      private

      def submitted_facts(migration_id:, source_config_name:, source_upper_position:, source_event:, source:)
        resolved = @context_resolver.from_submission(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_candidate: source
        )
        return resolved if resolved.failure?

        context = resolved.value!
        actor = Commands::Actor.new(kind: "agent", id: source.agent_id)
        common_extension = MigrationMetadataExtensionV1.new(attributed_actor: actor)
        intention_extension = MigrationMetadataExtensionV1.new(
          attributed_actor: actor,
          policy_version: source.lease_policy_version
        )
        Success([
          fact(
            context,
            Events::CandidateCreatedV1.new(candidate_id: context.candidate_id),
            "create-candidate",
            common_extension
          ),
          fact(
            context,
            Events::CandidateAssignedToAttemptV1.new(
              candidate_id: context.candidate_id,
              attempt_id: context.attempt_id,
              work_item_id: context.work_item_id,
              change_set_id: context.change_set_id
            ),
            "assign-candidate-to-attempt",
            common_extension
          ),
          fact(
            context,
            Events::CandidateAssignedToRepositoryV1.new(
              candidate_id: context.candidate_id,
              repository_id: context.repository_id
            ),
            "assign-candidate-to-repository",
            common_extension
          ),
          fact(
            context,
            Events::CandidateTargetBranchSelectedV1.new(
              candidate_id: context.candidate_id,
              target_branch: source.target_branch
            ),
            "select-candidate-target-branch",
            common_extension
          ),
          fact(
            context,
            Events::CandidateCommitRangeDeclaredV1.new(
              candidate_id: context.candidate_id,
              object_format: source.object_format,
              base_commit_oid: source.base_commit_oid,
              head_commit_oid: source.head_commit_oid
            ),
            "declare-candidate-commit-range",
            common_extension
          ),
          fact(
            context,
            Events::CandidateCheckpointKindSelectedV1.new(
              candidate_id: context.candidate_id,
              checkpoint_kind: source.checkpoint_kind
            ),
            "select-candidate-checkpoint-kind",
            common_extension
          ),
          fact(
            context,
            Events::CandidateWorkIntentionSetAssignedV1.new(
              candidate_id: context.candidate_id,
              intention_set_id: source.lease_set_id
            ),
            "assign-candidate-work-intention-set",
            intention_extension
          ),
          fact(
            context,
            Events::CandidateSubmittedV3.new(candidate_id: context.candidate_id),
            "submit-candidate",
            common_extension
          )
        ])
      end

      def coalesce_attempt_assignment(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        resolved = @context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.candidate_event
        )
        return resolved if resolved.failure?
        return Success([]) if matching_attachment?(source, resolved.value!.source_candidate)

        Failure(inconsistent(source_event, "Candidate attachment disagrees with its submission"))
      end

      def fact(context, event, step_name, metadata_extension)
        TransformedFactV1.new(
          target_stream: context.candidate_stream,
          event:,
          markers: context.markers,
          step_name:,
          metadata_extension:
        )
      end

      def matching_attachment?(attachment, candidate)
        [
          attachment.candidate_id,
          attachment.change_set_id,
          attachment.work_item_id,
          attachment.attempt_id,
          attachment.repository_id,
          attachment.target_branch,
          attachment.object_format,
          attachment.base_commit_oid,
          attachment.head_commit_oid,
          attachment.checkpoint_kind,
          attachment.manifest_digest,
          attachment.build_context_digest
        ] == [
          candidate.candidate_id,
          candidate.change_set_id,
          candidate.work_item_id,
          candidate.attempt_id,
          candidate.repository_id,
          candidate.target_branch,
          candidate.object_format,
          candidate.base_commit_oid,
          candidate.head_commit_oid,
          candidate.checkpoint_kind,
          candidate.manifest_digest,
          candidate.build_context_digest
        ]
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
