# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ExpireResourceLease < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expected_expires_at, Types::Timestamp
    end
  end
end
