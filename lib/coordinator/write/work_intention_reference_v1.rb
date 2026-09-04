# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionReferenceV1 < Value
    attribute :intention_id, Types::UuidV7
    attribute :resource_id, Types::ResourceId
  end
end
