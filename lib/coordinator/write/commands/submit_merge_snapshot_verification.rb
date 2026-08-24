# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class SubmitMergeSnapshotVerification < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :merge_snapshot_id, Types::Identifier
      attribute :binding, MergeSnapshotVerifications::BindingV1
      attribute :assessment, MergeSnapshotVerifications::AssessmentV1
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
    end
  end
end
