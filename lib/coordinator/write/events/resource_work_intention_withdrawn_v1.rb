# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ResourceWorkIntentionWithdrawnV1 < Base
      contract type: "ResourceWorkIntentionWithdrawn", version: 1

      attribute :intention_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :fencing_token, Types::FencingToken
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000).optional
    end
  end
end
