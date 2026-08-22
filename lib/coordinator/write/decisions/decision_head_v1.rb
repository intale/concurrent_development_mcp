# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionHeadV1 < Value
      attribute :decision_id, Types::Identifier
      attribute :decision_revision, Types::StreamRevision
      attribute :event, EventReference
    end
  end
end
