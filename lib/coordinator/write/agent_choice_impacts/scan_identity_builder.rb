# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ScanIdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def start(source_event:, policy_version:)
        document = ScanIdentityDocumentV1.new(
          schema: "agent-choice-impact-scan-identity/v1",
          policy_version:,
          source_event:
        )
        Types::InternalCommandId["internal:choice-impact-scan-v1:#{digest(document)}"]
      end

      def progress(checkpoint_event:, policy_version:)
        document = ScanProgressIdentityDocumentV1.new(
          schema: "agent-choice-impact-scan-progress-identity/v1",
          policy_version:,
          checkpoint_event:
        )
        Types::InternalCommandId["internal:choice-impact-progress-v1:#{digest(document)}"]
      end

      private

      def digest(document)
        @canonical_json.sha256(document.to_h).delete_prefix("sha256:")
      end
    end
  end
end
