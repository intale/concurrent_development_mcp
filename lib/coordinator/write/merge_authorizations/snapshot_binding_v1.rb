# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class SnapshotBindingV1 < Value
      attribute :registration_event, EventReference
      attribute :snapshot_digest, Types::Sha256Digest
      attribute :verification_event, EventReference
      attribute :verification_digest, Types::Sha256Digest
    end
  end
end
