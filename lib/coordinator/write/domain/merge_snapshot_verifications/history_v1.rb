# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeSnapshotVerifications
      class HistoryV1 < Value
        Observation = Types.Instance(Coordinator::Write::MergeSnapshotVerifications::EvidenceObservationV1)
        Assignment = Types.Instance(Coordinator::Write::MergeSnapshotVerifications::AssignmentObservationV1)

        attribute :snapshot, Types.Instance(Coordinator::Write::MergeSnapshots::StateV2).optional
        attribute :assignments,
                  Types::Array.of(Assignment).constrained(
                    max_size: Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT + 1
                  )
        attribute :submissions,
                  Types::Array.of(Observation).constrained(
                    max_size: Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT + 1
                  )
        attribute :verified,
                  Types.Instance(Coordinator::Write::MergeSnapshotVerifications::VerifiedObservationV2).optional

        def absent?
          snapshot.nil?
        end

        def terminal?
          !verified.nil?
        end

        def duplicate?(verification_input_digest)
          submissions.any? do |observation|
            observation.verification_input_digest == verification_input_digest
          end
        end

        def limit_reached?
          submissions.length >= Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT
        end
      end
    end
  end
end
