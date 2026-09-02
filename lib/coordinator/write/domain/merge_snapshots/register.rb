# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeSnapshots
      class Register
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          snapshot_digest_builder: Coordinator::Write::MergeSnapshots::SnapshotDigestBuilder.new
        )
          @stream_factory = stream_factory
          @snapshot_digest_builder = snapshot_digest_builder
        end

        def call(state:, command:, commit_identity:, snapshot_event:, registered_at:)
          denial = denied(state:, command:)
          return denial if denial

          members = state.candidates.map { member(_1) }
          snapshot = Events::MergeSnapshotRegisteredV1.new(
            merge_snapshot_id: command.merge_snapshot_id,
            repository_id: command.repository_id,
            target_branch: command.target_branch,
            object_format: command.object_format,
            target_base_commit_oid: command.target_base_commit_oid,
            ordered_candidates: members,
            merge_commit_oid: command.merge_commit_oid,
            producer: command.producer,
            run_id: command.run_id,
            produced_at: command.produced_at,
            snapshot_digest: @snapshot_digest_builder.call(command:, members:),
            policy_version: command.policy_version,
            evidence_status: "attributed_unverified",
            registered_at:
          )
          registration = Events::MergeSnapshotCommitRegisteredV2.new(
            registry_id: commit_identity.registry_id,
            merge_snapshot_id: command.merge_snapshot_id,
            repository_id: command.repository_id,
            object_format: command.object_format,
            merge_commit_oid: command.merge_commit_oid,
            snapshot_event:,
            registered_at:
          )

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(stream: @stream_factory.merge_snapshot(command.merge_snapshot_id), event: snapshot),
                EventWrite.new(
                  stream: @stream_factory.merge_snapshot_commit(commit_identity.registry_id),
                  event: registration
                )
              ]
            )
          )
        end

        private

        def denied(state:, command:)
          return conflict(:merge_snapshot_id_already_used, "Merge snapshot ID is already registered", state.existing_snapshot) if state.existing_snapshot
          return conflict(:merge_commit_already_registered, "Merge commit is already registered", state.existing_commit) if state.existing_commit

          state.candidates.each do |history|
            candidate = history.candidate
            manifest = history.manifest
            return candidate_failure(:candidate_not_found, "Candidate does not exist", history) unless candidate
            return candidate_failure(:candidate_manifest_not_found, "Candidate manifest does not exist", history) unless manifest
            return candidate_failure(:candidate_head_mismatch, "Candidate head differs from the requested composition", history) unless candidate.head_commit_oid == history.requested.head_commit_oid
            return candidate_failure(:candidate_repository_mismatch, "Candidate belongs to another repository", history) unless candidate.repository_id == command.repository_id
            return candidate_failure(:candidate_target_branch_mismatch, "Candidate targets another branch", history) unless candidate.target_branch == command.target_branch
            return candidate_failure(:candidate_object_format_mismatch, "Candidate uses another Git object format", history) unless candidate.object_format == command.object_format
          end
          nil
        end

        def conflict(code, message, reference)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: { existing_event: reference.to_h }
            )
          )
        end

        def candidate_failure(code, message, history)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                candidate_id: history.requested.candidate_id,
                requested_head_commit_oid: history.requested.head_commit_oid
              }
            )
          )
        end

        def member(history)
          candidate = history.candidate
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
            candidate_event: history.candidate_event,
            manifest_event: history.manifest_event
          )
        end
      end
    end
  end
end
