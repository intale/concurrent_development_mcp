# frozen_string_literal: true

module Coordinator::Read
  class WorkIntentionSetViewV1 < Value
    attribute :set_id, Types::UuidV7
    attribute :change_set_id, Types::Identifier
    attribute :work_item_id, Types::Identifier
    attribute :attempt_id, Types::Identifier
    attribute :repository_id, Types::RepositoryId
    attribute :agent_id, Types::Identifier
    attribute :policy_version, Types::ResourceLeasePolicyVersion
    attribute :intentions,
              Types::Array.of(WorkIntentionViewV1)
                .constrained(min_size: 1, max_size: 32)
    attribute :created_event, Types.Instance(PgEventstore::Event)
    attribute :last_expanded_event, Types.Instance(PgEventstore::Event).optional
    attribute :last_renewed_event, Types.Instance(PgEventstore::Event).optional
    attribute :release_event, Types.Instance(PgEventstore::Event).optional
    attribute :declared_at, Types::Timestamp
    attribute :last_expanded_at, Types::Timestamp.optional
    attribute :last_renewed_at, Types::Timestamp.optional
    attribute :previous_expires_at, Types::Timestamp.optional
    attribute :expires_at, Types::Timestamp
    attribute :withdrawn_at, Types::Timestamp.optional
  end
end
