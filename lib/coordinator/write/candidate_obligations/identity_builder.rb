# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class IdentityBuilder
      PREFIX = "internal:candidate-compatibility-obligation-v1"

      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(source:, target:, policy_partition_event:, policy_head:, rule_version:)
        document = IdentityDocumentV1.new(
          schema: IdentityDocumentV1::SCHEMA,
          rule_version:,
          source_surface: source.subject.surface_event,
          target_surface: target.subject.surface_event,
          policy_partition_event:,
          policy_head:
        )
        digest = @canonical_json.sha256(document.to_h)
        obligation_id = Types::InternalCommandId["#{PREFIX}:#{digest.delete_prefix("sha256:")}"]
        IdentityV1.new(
          document:,
          digest:,
          obligation_id:
        )
      end
    end
  end
end
