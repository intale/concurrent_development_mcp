# frozen_string_literal: true

module Coordinator::Read
  class AttemptDefinitionViewV1 < Value
    attribute :attempt_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :work_item_id, Types::Identifier
    attribute :agent_id, Types::Identifier
    attribute :base_snapshots,
              Types::Array.of(Coordinator::Write::RepositorySnapshotV1).constrained(size: 1)
    attribute :authorization_event, Types.Instance(PgEventstore::Event)
    attribute :authorized_at, Types::Timestamp
    attribute :started_at, Types::Timestamp
  end
end
