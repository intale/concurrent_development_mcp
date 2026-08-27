# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AssessmentIdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(accepted_choice:, decision_change:, policy_version:)
        document = AssessmentIdentityDocumentV1.new(
          schema: "agent-choice-impact-assessment-identity/v1",
          policy_version:,
          accepted_choice:,
          decision_change:
        )
        digest = @canonical_json.sha256(document.to_h).delete_prefix("sha256:")
        Types::InternalCommandId["internal:choice-impact-v1:#{digest}"]
      end
    end
  end
end
