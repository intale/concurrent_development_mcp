# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class MergeSnapshotVerifiedV2 < EventMetadata
      attribute :verification_digest, Types::Sha256Digest
    end
  end
end
