# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionRelationsV1 < Value
      attribute :corrects, Types::DecisionIdentifiers
      attribute :supersedes, Types::DecisionIdentifiers
      attribute :exception_to, Types::DecisionIdentifiers
      attribute :revokes, Types::DecisionIdentifiers
    end
  end
end
