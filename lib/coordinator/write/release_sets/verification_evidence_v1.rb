# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class VerificationEvidenceV1 < Value
      Finding = VerificationFindingV1

      attribute :producer, EvidenceProducerV1
      attribute :run_id, Types::Identifier
      attribute :environment_digest, Types::Sha256Digest
      attribute :result_digest, Types::Sha256Digest
      attribute :outcome, Types::ReleaseSetVerificationOutcome
      attribute :findings, Types::Array.of(Finding).constrained(max_size: 32)
      attribute :produced_at, Types::Timestamp
    end
  end
end
