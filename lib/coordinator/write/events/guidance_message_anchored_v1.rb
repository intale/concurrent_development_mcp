# frozen_string_literal: true

module Coordinator::Write
  module Events
    class GuidanceMessageAnchoredV1 < Base
      contract type: "GuidanceMessageAnchored", version: 1

      attribute :conversation_id, Types::Identifier
      attribute :message_id, Types::Identifier
      attribute :anchor_kind, Types::String.enum("repository", "change_set", "work_item", "attempt")
      attribute :anchor_id, Types::Identifier
    end
  end
end
