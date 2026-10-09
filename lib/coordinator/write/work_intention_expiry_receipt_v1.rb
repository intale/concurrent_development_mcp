# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionExpiryReceiptV1 < Value
    attribute :resource_id, Types::ResourceId
    attribute :intention_id, Types::UuidV7
    attribute :intention_set_id, Types::UuidV7
    attribute :fencing_token, Types::FencingToken
    attribute :expires_at, Types::Timestamp
    attribute :expired_at, Types::Timestamp
  end
end
