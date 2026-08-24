# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeSnapshotVerifications
      class Submit
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          verified_digest_builder: Coordinator::Write::MergeSnapshotVerifications::VerifiedDigestBuilder.new
        )
          @stream_factory = stream_factory
          @verified_digest_builder = verified_digest_builder
        end

        def call(
          history:,
          command:,
          snapshot_evidence:,
          verification_id:,
          verification_input_digest:,
          submission_event:,
          submitted_at:
        )
          denial = denied(history:, command:, snapshot_evidence:, verification_input_digest:)
          return Failure(denial) if denial

          submission = Events::MergeSnapshotVerificationSubmittedV1.new(
            merge_snapshot_id: command.merge_snapshot_id,
            snapshot: snapshot_evidence,
            verification_id:,
            policy_version: command.policy_version,
            assessment: command.assessment,
            verification_input_digest:,
            submitted_at:
          )
          writes = [ write(command.merge_snapshot_id, submission) ]
          verified = verified_event(
            command:,
            snapshot_evidence:,
            verification_id:,
            verification_input_digest:,
            submission_event:,
            submitted_at:
          )
          writes << write(command.merge_snapshot_id, verified) if verified

          Success(EventPlan.new(writes:))
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

        def verified_event(
          command:,
          snapshot_evidence:,
          verification_id:,
          verification_input_digest:,
          submission_event:,
          submitted_at:
        )
          assessment = command.assessment
          return unless assessment.conclusion == "passed"
          return if assessment.findings.any? { %w[error critical].include?(_1.severity) }

          selected = Coordinator::Write::MergeSnapshotVerifications::VerificationDecisionReferenceV1.new(
            verification_id:,
            evidence_kind: assessment.evidence_kind,
            conclusion: assessment.conclusion,
            result_digest: assessment.result_digest,
            verification_input_digest:,
            event: submission_event
          )
          Events::MergeSnapshotVerifiedV1.new(
            merge_snapshot_id: command.merge_snapshot_id,
            snapshot: snapshot_evidence,
            policy_version: command.policy_version,
            selected_verification: selected,
            verification_digest: @verified_digest_builder.call(
              merge_snapshot_id: command.merge_snapshot_id,
              snapshot_digest: snapshot_evidence.snapshot.snapshot_digest,
              policy_version: command.policy_version,
              selected_verification: selected
            ),
            verified_at: submitted_at
          )
        end

        def write(merge_snapshot_id, event)
          EventWrite.new(stream: @stream_factory.merge_snapshot(merge_snapshot_id), event:)
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
