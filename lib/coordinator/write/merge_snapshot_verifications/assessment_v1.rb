# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class AssessmentV1 < Value
      Finding = FindingV1

      attribute :evidence_kind, Types::MergeSnapshotVerificationEvidenceKind
      attribute :producer, ProducerV1
      attribute :run_id, Types::Identifier
      attribute :test_suite_digest, Types::Sha256Digest
      attribute :environment_digest, Types::Sha256Digest
      attribute :result_digest, Types::Sha256Digest
      attribute :conclusion, Types::VerificationEvidenceConclusion
      attribute :findings, Types::Array.of(Finding).constrained(max_size: 32)
      attribute :produced_at, Types::Timestamp
    end
  end
end
