# frozen_string_literal: true

module Coordinator::Write
  module Events
    class UserUtteranceForwardedByAgentV2 < Base
      contract type: "UserUtteranceForwardedByAgent", version: 2

      attribute :conversation_id, Types::Identifier
      attribute :message_id, Types::Identifier
      attribute :source, Types::String.enum("agent_forwarded")
      attribute :text, Types::GuidanceText
    end
  end
end
