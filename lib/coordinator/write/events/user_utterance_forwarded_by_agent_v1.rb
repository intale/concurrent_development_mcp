# frozen_string_literal: true

module Coordinator::Write
  module Events
    class UserUtteranceForwardedByAgentV1 < Base
      contract type: "UserUtteranceForwardedByAgent", version: 1

      attribute :message_id, Types::Identifier
      attribute :conversation_id, Types::Identifier
      attribute :text, Types::GuidanceText
      attribute :source, Types::String.enum("agent_forwarded")
      attribute :anchors, GuidanceAnchorsV1
      attribute :recorded_at, Types::Timestamp
    end
  end
end
