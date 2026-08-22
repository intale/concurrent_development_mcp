# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionValueV1 < Value
      attribute :schema, Types::DecisionValueSchema
      attribute :name, Types::InterpretationLabel.optional
      attribute :items, Types::InterpretationLabels.optional
      attribute :target_kind, Types::MergeTargetKind.optional
      attribute :target_id, Types::Identifier.optional
      attribute :action, Types::MergeAction.optional
    end
  end
end
