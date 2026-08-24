# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CompensationEvidenceV1 < Value
      attribute :repository_id, Types::RepositoryId
      attribute :integration_event, EventReference
      attribute :action, Types::ReleaseSetCompensationAction
      attribute :external_reference, Types::ReleaseSetExternalReference
      attribute :result_digest, Types::Sha256Digest
      attribute :producer, EvidenceProducerV1
      attribute :run_id, Types::Identifier
      attribute :compensated_at, Types::Timestamp
    end
  end
end
