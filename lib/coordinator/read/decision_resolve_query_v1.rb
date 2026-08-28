# frozen_string_literal: true

module Coordinator::Read
  class DecisionResolveQueryV1 < Value
    attribute :topic_id, Types::Identifier
    attribute :context, DecisionResolution::QueryContextV1
  end
end
