# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class ReleaseSetVerificationV2 < EventMetadata
      attribute :release_digest, Types::Sha256Digest
      attribute :verification_digest, Types::Sha256Digest
    end
  end
end
