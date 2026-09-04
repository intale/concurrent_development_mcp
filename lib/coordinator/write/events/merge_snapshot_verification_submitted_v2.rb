# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotVerificationSubmittedV2 < Base
      contract type: "MergeSnapshotVerificationSubmitted", version: 2

      attribute :verification_id, Types::UuidV7
      attribute :merge_snapshot_id, Types::Identifier
      attribute :assessment, MergeSnapshotVerifications::AssessmentV1
    end
  end
end
