# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotVerifiedV2 < Base
      contract type: "MergeSnapshotVerified", version: 2

      attribute :merge_snapshot_id, Types::Identifier
    end
  end
end
