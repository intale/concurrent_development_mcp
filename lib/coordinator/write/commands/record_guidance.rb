# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordGuidance < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :message_id, Types::Identifier
      attribute :conversation_id, Types::Identifier
      attribute :source, Types::GuidanceSource
      attribute :text, Types::GuidanceText
      attribute :anchors, GuidanceAnchorsV1
    end
  end
end
