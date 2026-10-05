# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateContextV1 < Value
      attribute :source_candidate, Events::CandidateSubmittedV2
      attribute :source_candidate_event, Types.Instance(PgEventstore::Event)
      attribute? :target_submission_event, EventReference.optional.default(nil)
      attribute :candidate_stream, StreamReference
      attribute :candidate_id, Types::UuidV7
      attribute :change_set_id, Types::UuidV7
      attribute :work_item_id, Types::UuidV7
      attribute :attempt_id, Types::UuidV7
      attribute :repository_id, Types::UuidV7
      attribute :intention_set_id, Types::UuidV7

      def markers
        [
          "candidate:#{candidate_id}",
          "change-set:#{change_set_id}",
          "work-item:#{work_item_id}",
          "attempt:#{attempt_id}",
          "repository:#{repository_id}",
          "object-format:#{source_candidate.object_format}",
          "head-commit-oid:#{source_candidate.head_commit_oid}",
          "work-intention-set:#{intention_set_id}"
        ]
      end
    end
  end
end
