# frozen_string_literal: true

module Coordinator::Read
  class DecisionResolveQueryV1 < Value
    attribute :topic_id, Types::String.enum("testing.framework")
    attribute :context, DecisionResolution::QueryContextV1
  end
end
