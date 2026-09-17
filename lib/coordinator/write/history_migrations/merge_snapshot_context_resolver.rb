# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeSnapshotContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        candidate_context_resolver:,
        target_event_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @candidate_context_resolver = candidate_context_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @schema_registry = schema_registry
      end

      def from_registration(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_registration:
      )
        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          registration_event: source_event,
          source_registration:,
          include_target_reference: false
        )
      end

      def from_stream(migration_id:, source_config_name:, source_upper_position:, source_event:)
        registration_event = @event_store.read_at(stream_for(source_event), 0)
        unless registration_event && registration_event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "merge snapshot registration is absent from the frozen source range"))
        end

        source_registration = load(registration_event)
        unless source_registration.is_a?(Events::MergeSnapshotRegisteredV1)
          return Failure(inconsistent(source_event, "merge snapshot stream does not begin with MergeSnapshotRegistered@1"))
        end

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          registration_event:,
          source_registration:,
          include_target_reference: true
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def from_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        registration_event = locate(source_reference)
        unless valid_reference?(registration_event, source_reference:, source_upper_position:)
          return Failure(inconsistent(source_event, "merge snapshot reference is absent from the frozen source range"))
        end

        source_registration = load(registration_event)
        unless source_registration.is_a?(Events::MergeSnapshotRegisteredV1)
          return Failure(inconsistent(source_event, "merge snapshot reference does not identify MergeSnapshotRegistered@1"))
        end

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          registration_event:,
          source_registration:,
          include_target_reference: true
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        registration_event:,
        source_registration:,
        include_target_reference:
      )
        validation = validate_registration(
          source_event:,
          registration_event:,
          source_registration:,
          source_upper_position:
        )
        return validation if validation.failure?

        snapshot = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: registration_event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "MergeSnapshot",
          identity_role: "merge-snapshot"
        )
        return snapshot if snapshot.failure?

        repository = resolve_repository(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_registration:
        )
        return repository if repository.failure?

        candidates = resolve_candidates(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_registration:
        )
        return candidates if candidates.failure?

        candidate_contexts, target_candidate_members = candidates.value!
        target_repository_id = repository.value!.target_stream.stream_id
        unless candidate_contexts.all? { _1.repository_id == target_repository_id }
          return Failure(inconsistent(source_event, "merge snapshot Candidate repository mappings disagree"))
        end
        target_stream = snapshot.value!.target_stream
        target_reference = if include_target_reference
          resolved = @target_event_reference_resolver.call_in_stream(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: reference_for(registration_event),
            target_stream:,
            target_event_type: "MergeSnapshotRegistered",
            target_step_name: "register-merge-snapshot"
          )
          return resolved if resolved.failure?

          resolved.value!
        end

        Success(
          MergeSnapshotMigrationContextV1.new(
            source_registration:,
            source_registration_event: registration_event,
            target_registration_event: target_reference,
            snapshot_stream: target_stream,
            merge_snapshot_id: target_stream.stream_id,
            repository_id: target_repository_id,
            candidate_contexts:,
            target_candidate_members:
          )
        )
      end

      def resolve_repository(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_registration:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "Repository",
            stream_id: source_registration.repository_id
          ),
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "Repository",
          identity_role: "repository"
        )
      end

      def resolve_candidates(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_registration:
      )
        contexts = []
        members = []
        source_registration.ordered_candidates.each do |member|
          resolved = @candidate_context_resolver.from_reference(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference: member.candidate_event
          )
          return resolved if resolved.failure?

          manifest = @candidate_context_resolver.load_reference(
            source_event:,
            source_upper_position:,
            source_reference: member.manifest_event
          )
          return manifest if manifest.failure?

          context = resolved.value!
          unless candidate_member_matches?(member, context.source_candidate, manifest.value!.payload)
            return Failure(inconsistent(source_event, "merge snapshot Candidate evidence is inconsistent"))
          end

          unless context.source_candidate.repository_id == source_registration.repository_id &&
              member.repository_id == source_registration.repository_id &&
              member.target_branch == source_registration.target_branch &&
              member.object_format == source_registration.object_format
            return Failure(inconsistent(source_event, "merge snapshot Candidate scope is inconsistent"))
          end

          target_manifest = @target_event_reference_resolver.call_in_stream(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: member.manifest_event,
            target_stream: context.candidate_stream,
            target_event_type: "CandidateChangeManifestCaptured",
            target_step_name: "capture-candidate-change-manifest"
          )
          return target_manifest if target_manifest.failure?

          contexts << context
          members << MergeSnapshots::CandidateMemberV1.new(
            candidate_id: context.candidate_id,
            change_set_id: context.change_set_id,
            work_item_id: context.work_item_id,
            attempt_id: context.attempt_id,
            repository_id: context.repository_id,
            target_branch: member.target_branch,
            object_format: member.object_format,
            base_commit_oid: member.base_commit_oid,
            head_commit_oid: member.head_commit_oid,
            manifest_digest: member.manifest_digest,
            candidate_event: context.target_submission_event ||
              raise(KeyError, "target Candidate submission reference is absent"),
            manifest_event: target_manifest.value!
          )
        end
        return Failure(inconsistent(source_event, "merge snapshot repeats a Candidate")) unless
          contexts.map(&:candidate_id).uniq.length == contexts.length

        Success([ contexts.freeze, members.freeze ])
      end

      def candidate_member_matches?(member, candidate, manifest)
        manifest.is_a?(Events::CandidateChangeManifestCapturedV1) &&
          [
            member.candidate_id,
            member.change_set_id,
            member.work_item_id,
            member.attempt_id,
            member.repository_id,
            member.target_branch,
            member.object_format,
            member.base_commit_oid,
            member.head_commit_oid,
            member.manifest_digest
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
            candidate.manifest_digest
          ] &&
          [
            manifest.candidate_id,
            manifest.repository_id,
            manifest.target_branch,
            manifest.object_format,
            manifest.base_commit_oid,
            manifest.head_commit_oid,
            manifest.manifest_digest
          ] == [
            candidate.candidate_id,
            candidate.repository_id,
            candidate.target_branch,
            candidate.object_format,
            candidate.base_commit_oid,
            candidate.head_commit_oid,
            candidate.manifest_digest
          ]
      end

      def validate_registration(source_event:, registration_event:, source_registration:, source_upper_position:)
        stream = stream_for(registration_event)
        valid = registration_event.type == "MergeSnapshotRegistered" &&
                registration_event.metadata.fetch("schema_version") == 1 &&
                registration_event.global_position <= source_upper_position &&
                registration_event.stream_revision.zero? &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "MergeSnapshot" &&
                stream.stream_id == source_registration.merge_snapshot_id &&
                registration_event.markers.include?("merge-snapshot:#{source_registration.merge_snapshot_id}")
        return Success() if valid

        Failure(inconsistent(source_event, "merge snapshot identity, schema, stream, revision, or markers are invalid"))
      end

      def locate(reference)
        @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
      end

      def valid_reference?(event, source_reference:, source_upper_position:)
        event &&
          event.id == source_reference.event_id &&
          event.type == source_reference.type &&
          event.global_position <= source_upper_position
      end

      def reference_for(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Merge snapshot source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
