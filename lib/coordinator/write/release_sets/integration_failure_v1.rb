# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class IntegrationFailureV1 < Value
      attribute :code, Types::ReleaseSetFailureCode
      attribute :summary, Types::ReleaseSetEvidenceSummary
      attribute :producer, EvidenceProducerV1
      attribute :run_id, Types::Identifier
      attribute :result_digest, Types::Sha256Digest
      attribute :occurred_at, Types::Timestamp
    end
  end
end
