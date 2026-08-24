# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeSnapshots
      class RegistrationState < Value
        History = Types.Instance(Coordinator::Write::MergeSnapshots::CandidateHistoryV1)

        attribute :existing_snapshot, EventReference.optional
        attribute :existing_commit, EventReference.optional
        attribute :candidates,
                  Types::Array.of(History)
                    .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      end
    end
  end
end
