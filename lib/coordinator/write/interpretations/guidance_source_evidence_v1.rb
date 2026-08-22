# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class GuidanceSourceEvidenceV1 < Value
      attribute :message_id, Types::Identifier
      attribute :text, Types::GuidanceText
      attribute :anchors, GuidanceAnchorsV1
      attribute :event, EventReference
    end
  end
end
