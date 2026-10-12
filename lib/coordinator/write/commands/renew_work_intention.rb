# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RenewWorkIntention < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :renewal_id, Types::UuidV7
      attribute :intention_set_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :intention_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :fencing_token, Types::FencingToken
      attribute :expires_at, Types::Timestamp
    end
  end
end
