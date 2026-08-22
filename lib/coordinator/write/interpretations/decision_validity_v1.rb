# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionValidityV1 < Value
      attribute :valid_from, Types::Timestamp.optional
      attribute :valid_until, Types::Timestamp.optional
      attribute :until_event, UntilEventConditionV1.optional
    end
  end
end
