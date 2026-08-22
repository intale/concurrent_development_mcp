# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionScopeProvenanceV1 < Value
      attribute :kind, Types::ScopeProvenanceKind
      attribute :anchor_level, Types::ScopeAnchorLevel
      attribute :source_message_id, Types::Identifier
    end
  end
end
