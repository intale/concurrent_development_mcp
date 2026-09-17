# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelCandidateContextV1 < Value
      attribute :source_candidate_id, Types::Identifier
      attribute :source_change_set_id, Types::Identifier
      attribute :source_work_item_id, Types::Identifier
      attribute :source_attempt_id, Types::Identifier
      attribute :source_repository_id, Types::RepositoryId
      attribute :source_intention_set_id, Types::UuidV7
      attribute :candidate_stream, StreamReference
      attribute :candidate_id, Types::UuidV7
      attribute :change_set_id, Types::UuidV7
      attribute :work_item_id, Types::UuidV7
      attribute :attempt_id, Types::UuidV7
      attribute :repository_id, Types::UuidV7
      attribute :intention_set_id, Types::UuidV7
      attribute :object_format, Types::GitObjectFormat
      attribute :head_commit_oid, Types::GitOid

      def markers
        [
          "candidate:#{candidate_id}",
          "change-set:#{change_set_id}",
          "work-item:#{work_item_id}",
          "attempt:#{attempt_id}",
          "repository:#{repository_id}",
          "object-format:#{object_format}",
          "head-commit-oid:#{head_commit_oid}",
          "work-intention-set:#{intention_set_id}"
        ]
      end
    end
  end
end
