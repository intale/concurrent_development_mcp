# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ExpireResourceLease < Value
      attribute :command_id, Types::InternalCommandId
      attribute :actor, Actor
      attribute :resource_id, Types::ResourceId
      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expected_expires_at, Types::Timestamp
    end
  end
end
