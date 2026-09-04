# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotVerificationAssignedV1 < Base
      contract type: "MergeSnapshotVerificationAssigned", version: 1

      attribute :verification_id, Types::UuidV7
      attribute :merge_snapshot_id, Types::Identifier
    end
  end
end
