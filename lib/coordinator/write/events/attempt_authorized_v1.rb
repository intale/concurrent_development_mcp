# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptAuthorizedV1 < Base
      Snapshot = RepositorySnapshotV1

      contract type: "AttemptAuthorized", version: 1

      attribute :attempt_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :agent_id, Types::Identifier
      attribute :base_snapshots, Types::Array.of(Snapshot).constrained(size: 1)
      attribute :authorized_at, Types::Timestamp
    end
  end
end
