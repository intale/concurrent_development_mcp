# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ResourceWorkIntentionRenewedV1 < Base
      contract type: "ResourceWorkIntentionRenewed", version: 1

      attribute :intention_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :fencing_token, Types::FencingToken
      attribute :expires_at, Types::Timestamp
    end
  end
end
