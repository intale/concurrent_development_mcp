# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ExpandWriteSet < Value
      Resource = Types.Instance(FileResourceV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :repository_id, Types::UuidV7
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    end
  end
end
