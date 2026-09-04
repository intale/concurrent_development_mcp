# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class ReleaseSetPreparedV2 < EventMetadata
      attribute :release_digest, Types::Sha256Digest
    end
  end
end
