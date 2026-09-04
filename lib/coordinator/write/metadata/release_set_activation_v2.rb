# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class ReleaseSetActivationV2 < EventMetadata
      attribute :activation_digest, Types::Sha256Digest
      attribute :release_digest, Types::Sha256Digest
      attribute :verification_digest, Types::Sha256Digest
    end
  end
end
