# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class RepositoryIntegrationV2 < EventMetadata
      attribute :integration_digest, Types::Sha256Digest
      attribute :observation_digest, Types::Sha256Digest.optional
      attribute :release_digest, Types::Sha256Digest
    end
  end
end
