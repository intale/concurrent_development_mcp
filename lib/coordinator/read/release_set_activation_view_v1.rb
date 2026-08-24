# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetActivationViewV1 < Value
    attribute :verification_event, Coordinator::Write::EventReference
    attribute :verification_digest, Types::Sha256Digest
    attribute :activation_point, Coordinator::Write::ReleaseSets::ActivationPointV1
    attribute :activation_digest, Types::Sha256Digest
    attribute :policy_version, Types::ReleaseSetActivationPolicyVersion
    attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
    attribute :recorded_at, Types::Timestamp
    attribute :source, ReleaseSetSourceEvidenceV1
  end
end
