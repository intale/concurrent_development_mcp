# frozen_string_literal: true

module Coordinator::Write
  module Events
    class UserUtteranceRecordedV2 < Base
      contract type: "UserUtteranceRecorded", version: 2

      attribute :conversation_id, Types::Identifier
      attribute :message_id, Types::Identifier
      attribute :source, Types::String.enum("user")
      attribute :text, Types::GuidanceText
    end
  end
end
