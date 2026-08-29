# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ReserveWriteSet < Value
      Resource = Types.Instance(ResourceLeaseTargetV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::UuidV7
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
      attribute :lease_duration_seconds, Types::LeaseDurationSeconds
    end
  end
end
