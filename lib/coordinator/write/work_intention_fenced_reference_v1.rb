# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionFencedReferenceV1 < Value
    attribute :resource_id, Types::ResourceId
    attribute :intention_id, Types::UuidV7
    attribute :fencing_token, Types::FencingToken
  end
end
