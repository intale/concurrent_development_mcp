# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeSnapshotVerifications
      class Verify
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(history:, command:)
          return Failure(error(:merge_snapshot_not_found, "Merge snapshot does not exist", command)) if history.absent?

          submission = history.submissions.find do |observation|
            observation.submission.verification_id == command.verification_id
          end
          unless submission
            return Failure(error(:merge_snapshot_verification_not_found, "Merge verification does not exist", command))
          end
          unless submission.policy_version == command.policy_version
            return Failure(error(:merge_snapshot_verification_policy_mismatch, "Merge verification policy does not match", command))
          end
          if history.terminal?
            return Success(nil) if history.verified.selected.verification_id == command.verification_id

            return Failure(error(:merge_snapshot_already_verified, "Merge snapshot is already verified", command))
          end
          return Success(nil) unless qualifying?(submission.submission.assessment)

          stream = @stream_factory.merge_snapshot(command.merge_snapshot_id)
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream:,
                  event: Events::MergeSnapshotVerificationSelectedV1.new(
                    merge_snapshot_id: command.merge_snapshot_id,
                    verification_id: command.verification_id
                  )
                ),
                EventWrite.new(
                  stream:,
                  event: Events::MergeSnapshotVerifiedV2.new(
                    merge_snapshot_id: command.merge_snapshot_id
                  )
                )
              ]
            )
          )
        end

        private

        def qualifying?(assessment)
          assessment.conclusion == "passed" &&
            assessment.findings.none? { %w[error critical].include?(_1.severity) }
        end

        def error(code, message, command)
          OutcomeError.new(
            code:,
            message:,
            details: {
              merge_snapshot_id: command.merge_snapshot_id,
              verification_id: command.verification_id
            }
          )
        end
      end
    end
  end
end
