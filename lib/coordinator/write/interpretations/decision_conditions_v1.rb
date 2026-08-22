# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionConditionsV1 < Value
      attribute :phases, Types::Array.of(Types::DecisionPhase).constrained(max_size: 5)
      attribute :languages, Types::ScopeIdentifiers
      attribute :tags, Types::ScopeIdentifiers
      attribute :repository_kinds, Types::ScopeIdentifiers
      attribute :artifact_kinds, Types::ScopeIdentifiers
      attribute :environments, Types::ScopeIdentifiers
    end
  end
end
