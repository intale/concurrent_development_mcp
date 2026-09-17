# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class ReleaseSetLegacyDigestBuilder
      DOCUMENTS = {
        release: [ LegacyReleaseDigestDocumentV1, "release-set/v1" ],
        integration: [ LegacyRepositoryIntegrationDigestDocumentV1, "release-set-integration/v1" ],
        verification: [ LegacyReleaseVerificationDigestDocumentV1, "release-set-verification/v1" ],
        activation: [ LegacyReleaseActivationDigestDocumentV1, "release-set-activation/v1" ],
        completion: [ LegacyReleaseCompletionDigestDocumentV1, "release-set-completion/v1" ]
      }.freeze

      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(kind, **attributes)
        document, schema = DOCUMENTS.fetch(kind)
        @canonical_json.sha256(document.new(schema:, **attributes).to_h)
      end
    end
  end
end
