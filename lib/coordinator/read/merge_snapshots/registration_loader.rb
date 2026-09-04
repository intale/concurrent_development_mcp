# frozen_string_literal: true

module Coordinator::Read
  module MergeSnapshots
    class RegistrationLoader
      def initialize(candidate_loader:)
        @candidate_loader = candidate_loader
      end

      def call(event, registration:)
        members = registration.ordered_candidates.map do |candidate_id|
          candidate = @candidate_loader.call(candidate_id)
          unless candidate.repository_id == registration.repository_id &&
                 candidate.target_branch == registration.target_branch &&
                 candidate.object_format == registration.object_format
            raise InvalidProjectionSource,
                  "Merge snapshot Candidate #{candidate_id} does not match its registration"
          end

          Coordinator::Write::MergeSnapshots::CandidateMemberV1.new(
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
            candidate_event: event_reference(candidate.submitted_event),
            manifest_event: event_reference(candidate.manifest_event)
          )
        end

        MergeSnapshotRegistrationViewV2.new(
          merge_snapshot_id: registration.merge_snapshot_id,
          repository_id: registration.repository_id,
          target_branch: registration.target_branch,
          object_format: registration.object_format,
          target_base_commit_oid: registration.target_base_commit_oid,
          ordered_candidates: members,
          merge_commit_oid: registration.merge_commit_oid,
          producer: registration.producer,
          run_id: registration.run_id,
          produced_at: registration.produced_at,
          snapshot_digest: event.metadata.fetch("snapshot_digest"),
          policy_version: event.metadata.fetch("policy_version"),
          evidence_status: "attributed_unverified"
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def event_reference(event)
        Coordinator::Write::EventReference.new(
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
