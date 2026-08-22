# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class TopicDefinitionV1 < Value
      attribute :topic_id, Types::SupportedInterpretationTopic
      attribute :parent_topic_id, Types::Identifier
      attribute :value_schema, Types::DecisionValueSchema
      attribute :resolution_strategy, Types::ResolutionStrategy
      attribute :inheritable, Types::Bool
      attribute :default_modality, Types::DecisionModality
      attribute :default_enforcement, Types::EnforcementLevel
      attribute :conflict_dimension, Types::Identifier
      attribute :ontology_version, Types::Integer.constrained(eql: 1)
      attribute :aliases, Types::ScopeIdentifiers
    end
  end
end
