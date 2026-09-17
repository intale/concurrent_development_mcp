# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class WorkIntentionMigrationContextV1 < Value
      Member = Types.Instance(WorkIntentionMemberMigrationV1)

      attribute :target_set_stream, StreamReference
      attribute :set_id, Types::UuidV7
      attribute :repository_id, Types::RepositoryId
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_markers,
                Types::Array.of(Types::ResourceMarker).constrained(min_size: 1, max_size: 3)
      attribute :members,
                Types::Array.of(Member).constrained(
                  min_size: 1,
                  max_size: WorkIntentionPolicyV1::MAXIMUM_SET_SIZE
                )
    end
  end
end
