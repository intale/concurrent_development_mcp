# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkIntentionAddedToSetV1 < Base
      contract type: "WorkIntentionAddedToSet", version: 1

      attribute :set_id, Types::UuidV7
      attribute :intention_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
    end
  end
end
