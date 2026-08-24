# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class IntegrationDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(**attributes)
        @canonical_json.sha256(
          IntegrationDigestDocumentV1.new(schema: "release-set-integration/v1", **attributes).to_h
        )
      end
    end
  end
end
