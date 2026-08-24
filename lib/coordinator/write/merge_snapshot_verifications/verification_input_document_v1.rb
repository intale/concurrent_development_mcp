# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class VerificationInputDocumentV1 < Value
      attribute :schema, Types::String.enum("merge-snapshot-verification-input/v1")
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
      attribute :snapshot, SnapshotEvidenceV1
      attribute :assessment, AssessmentV1
    end
  end
end
