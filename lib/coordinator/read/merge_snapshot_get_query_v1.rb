# frozen_string_literal: true

module Coordinator::Read
  class MergeSnapshotGetQueryV1 < Value
    attribute :merge_snapshot_id, Types::Identifier
  end
end
