# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class IdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(name:, scope:)
        document = IdentityDocumentV1.new(
          schema: IdentityDocumentV1::SCHEMA,
          name:,
          scope:
        )
        digest = @canonical_json.sha256(document.to_h).delete_prefix("sha256:")

        IdentityV1.new(skill_id: "skill:v1:#{digest}", name:, scope:)
      end
    end
  end
end
