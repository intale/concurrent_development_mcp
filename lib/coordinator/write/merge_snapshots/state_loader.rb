# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class StateLoader
      def initialize(
        event_store:,
        candidate_state_loader: Candidates::StateLoader.new(event_store:),
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @candidate_state_loader = candidate_state_loader
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(merge_snapshot_id)
        persisted = @event_store.read(
          @stream_factory.merge_snapshot(merge_snapshot_id),
          EventQueries::MERGE_SNAPSHOT_REGISTRATION
        ).first
        return unless persisted

        registration = @schema_registry.load(
          type: persisted.type,
          schema_version: persisted.metadata.fetch("schema_version"),
          data: persisted.data
        )
        unless registration.is_a?(Events::MergeSnapshotRegisteredV2) &&
               registration.merge_snapshot_id == merge_snapshot_id
          raise InvalidMergeSnapshotCandidateHistory, "Merge snapshot registration is invalid"
        end

        members = registration.ordered_candidates.map do |candidate_id|
          candidate = @candidate_state_loader.call(candidate_id)
          unless candidate && candidate_matches_registration?(candidate, registration)
            raise InvalidMergeSnapshotCandidateHistory,
                  "Merge snapshot Candidate #{candidate_id} no longer matches its registration"
          end

          CandidateMemberV1.new(
            candidate_id: candidate.candidate_id,
            change_set_id: candidate.change_set_id,
            work_item_id: candidate.work_item_id,
            attempt_id: candidate.attempt_id,
            repository_id: candidate.repository_id,
            target_branch: candidate.target_branch,
            object_format: candidate.object_format,
            base_commit_oid: candidate.base_commit_oid,
            head_commit_oid: candidate.head_commit_oid,
            manifest_digest: candidate.manifest_digest,
            candidate_event: candidate.submission_event,
            manifest_event: candidate.manifest_event
          )
        end.freeze

        StateV2.new(
          merge_snapshot_id: registration.merge_snapshot_id,
          repository_id: registration.repository_id,
          target_branch: registration.target_branch,
          object_format: registration.object_format,
          target_base_commit_oid: registration.target_base_commit_oid,
          merge_commit_oid: registration.merge_commit_oid,
          ordered_candidates: members,
          producer: registration.producer,
          run_id: registration.run_id,
          produced_at: registration.produced_at,
          snapshot_digest: persisted.metadata.fetch("snapshot_digest"),
          registration_event: event_reference(persisted)
        )
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError => error
        raise InvalidMergeSnapshotCandidateHistory, error.message
      end

      private

      def candidate_matches_registration?(candidate, registration)
        candidate.repository_id == registration.repository_id &&
          candidate.target_branch == registration.target_branch &&
          candidate.object_format == registration.object_format
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
