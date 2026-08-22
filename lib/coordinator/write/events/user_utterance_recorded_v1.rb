# frozen_string_literal: true

module Coordinator::Write
  module Events
    class UserUtteranceRecordedV1 < Base
      contract type: "UserUtteranceRecorded", version: 1

      attribute :message_id, Types::Identifier
      attribute :conversation_id, Types::Identifier
      attribute :text, Types::GuidanceText
      attribute :source, Types::String.enum("mcp_client")
      attribute :anchors, GuidanceAnchorsV1
      attribute :recorded_at, Types::Timestamp
    end
  end
end
