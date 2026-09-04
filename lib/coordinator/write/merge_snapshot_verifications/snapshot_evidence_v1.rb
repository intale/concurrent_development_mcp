# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class SnapshotEvidenceV1 < Value
      attribute :snapshot, MergeSnapshots::StateV2
      attribute :event, EventReference
    end
  end
end
