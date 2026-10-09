# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ExpireWorkIntention < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :resource_id, Types::ResourceId
      attribute :intention_id, Types::UuidV7
      attribute :intention_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expected_expires_at, Types::Timestamp
    end
  end
end
