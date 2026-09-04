# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class MergeSnapshotV2 < EventMetadata
      attribute :snapshot_digest, Types::Sha256Digest
    end
  end
end
