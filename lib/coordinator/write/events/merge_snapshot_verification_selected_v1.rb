# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotVerificationSelectedV1 < Base
      contract type: "MergeSnapshotVerificationSelected", version: 1

      attribute :merge_snapshot_id, Types::Identifier
      attribute :verification_id, Types::UuidV7
    end
  end
end
