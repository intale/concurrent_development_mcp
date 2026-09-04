# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class MergeSnapshotVerificationV2 < EventMetadata
      attribute :verification_input_digest, Types::Sha256Digest
    end
  end
end
