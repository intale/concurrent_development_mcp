# frozen_string_literal: true

module Coordinator::Write
  module DecisionContexts
    class Builder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(context:, observations:, resolution:, resolved_at:)
        document = ContextDocumentV1.new(
          schema: "decision-context/v1",
          resolution_policy: "testing-framework-resolution/v1",
          topic_id: "testing.framework",
          query_context: context,
          partitions: observations,
          effective_decision: resolution.effective_decision,
          shadowed_decisions: resolution.shadowed_decisions,
          conflict: resolution.conflict
        )
        ContextV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h),
          resolved_at:
        )
      end
    end
  end
end
