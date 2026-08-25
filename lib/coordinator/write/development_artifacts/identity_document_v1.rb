# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class IdentityDocumentV1 < Value
      SCHEMA = "development-artifact-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :source_kind, Types::DevelopmentArtifactSourceKind
      attribute :source_locator, Types::DevelopmentArtifactSourceLocator
      attribute :content_sha256, Types::Sha256Digest
    end
  end
end
