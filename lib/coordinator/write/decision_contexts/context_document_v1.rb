# frozen_string_literal: true

module Coordinator::Write
  module DecisionContexts
    class ContextDocumentV1 < Value
      Partition = PartitionObservationV1
      Shadowed = ShadowedDecisionV1

      attribute :schema, Types::String.enum("decision-context/v1")
      attribute :resolution_policy, Types::String.enum("testing-framework-resolution/v1")
      attribute :topic_id, Types::String.enum("testing.framework")
      attribute :query_context, QueryContextV1
      attribute :partitions, Types::Array.of(Partition).constrained(min_size: 4, max_size: 5)
      attribute :effective_decision, ResolvedDecisionV1.optional
      attribute :shadowed_decisions, Types::Array.of(Shadowed).constrained(max_size: 32)
      attribute :conflict, ConflictV1.optional
    end
  end
end
