# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AcquireWorkItem < Value
      Snapshot = Types.Instance(RepositorySnapshotV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :base_snapshots, Types::Array.of(Snapshot).constrained(max_size: 100)
    end
  end
end
