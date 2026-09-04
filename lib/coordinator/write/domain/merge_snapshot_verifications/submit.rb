# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeSnapshotVerifications
      class Submit
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new
        )
          @stream_factory = stream_factory
        end

        def call(
          history:,
          command:,
          snapshot_evidence:,
          verification_id:,
          verification_input_digest:
        )
          denial = denied(history:, command:, snapshot_evidence:, verification_input_digest:)
          return Failure(denial) if denial

          submission = Events::MergeSnapshotVerificationSubmittedV2.new(
            verification_id:,
            merge_snapshot_id: command.merge_snapshot_id,
            assessment: command.assessment
          )
          assignment = Events::MergeSnapshotVerificationAssignedV1.new(
            verification_id:,
            merge_snapshot_id: command.merge_snapshot_id
          )

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(stream: @stream_factory.merge_verification(verification_id), event: submission),
                EventWrite.new(stream: @stream_factory.merge_snapshot(command.merge_snapshot_id), event: assignment)
              ]
            )
          )
        end

        private

        def denied(history:, command:, snapshot_evidence:, verification_input_digest:)
          return error(:merge_snapshot_not_found, "Merge snapshot does not exist", command) if history.absent?
          return error(:merge_snapshot_already_verified, "Merge snapshot is already verified", command) if history.terminal?
          unless binding_matches?(command.binding, snapshot_evidence)
            return error(
              :merge_snapshot_verification_binding_stale,
              "Merge snapshot verification is bound to stale snapshot evidence",
              command,
              current_snapshot_event: snapshot_evidence.event.to_h,
              current_snapshot_digest: snapshot_evidence.snapshot.snapshot_digest
            )
          end
          if history.duplicate?(verification_input_digest)
            return error(
              :merge_snapshot_verification_already_submitted,
              "This merge snapshot verification was already submitted",
              command,
              verification_input_digest:
            )
          end
          return unless history.limit_reached?

          error(
            :merge_snapshot_verification_limit_reached,
            "Merge snapshot has reached its verification submission limit",
            command,
            maximum_count: Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT
          )
        end

        def binding_matches?(binding, evidence)
          snapshot = evidence.snapshot
          binding.snapshot_event == evidence.event &&
            binding.snapshot_digest == snapshot.snapshot_digest &&
            binding.repository_id == snapshot.repository_id &&
            binding.target_branch == snapshot.target_branch &&
            binding.object_format == snapshot.object_format &&
            binding.target_base_commit_oid == snapshot.target_base_commit_oid &&
            binding.merge_commit_oid == snapshot.merge_commit_oid &&
            binding.ordered_candidates.map(&:to_h) == snapshot.ordered_candidates.map do |candidate|
              { candidate_id: candidate.candidate_id, head_commit_oid: candidate.head_commit_oid }
            end
        end

        def error(code, message, command, details = {})
          OutcomeError.new(
            code:,
            message:,
            details: { merge_snapshot_id: command.merge_snapshot_id }.merge(details)
          )
        end
      end
    end
  end
end
