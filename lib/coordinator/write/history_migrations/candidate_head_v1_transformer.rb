# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateHeadV1Transformer
      include Dry::Monads[:result]

      def initialize(context_resolver:, stream_identity_allocator:, compound_marker_builder:)
        @context_resolver = context_resolver
        @stream_identity_allocator = stream_identity_allocator
        @compound_marker_builder = compound_marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        resolved = @context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source_payload.candidate_event
        )
        return resolved if resolved.failure?

        context = resolved.value!
        unless head_matches?(source_payload, context.source_candidate)
          return Failure(inconsistent(source_event, "Candidate head registration disagrees with its submission"))
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
        marker = head_marker(context.repository_id, source_payload)
        Success([
          TransformedFactV1.new(
            target_stream:,
            event: Events::CandidateHeadRegisteredV2.new(
              registry_id: target_stream.stream_id,
              candidate_id: context.candidate_id,
              attempt_id: context.attempt_id,
              repository_id: context.repository_id,
              object_format: source_payload.object_format,
              head_commit_oid: source_payload.head_commit_oid
            ),
            markers: context.markers + [ marker ],
            step_name: "register-candidate-head",
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              marker_codec_version: Candidates::HeadIdentityBuilder::MARKER_CODEC_VERSION
            )
          )
        ])
      end

      private

      def head_matches?(head, candidate)
        [
          head.candidate_id,
          head.attempt_id,
          head.repository_id,
          head.object_format,
          head.head_commit_oid
        ] == [
          candidate.candidate_id,
          candidate.attempt_id,
          candidate.repository_id,
          candidate.object_format,
          candidate.head_commit_oid
        ]
      end

      def head_marker(repository_id, head)
        @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "candidate-head-identity",
            components: [
              "repository:#{repository_id}",
              "object-format:#{head.object_format}",
              "head-commit-oid:#{head.head_commit_oid}"
            ]
          )
        ).marker
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
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
