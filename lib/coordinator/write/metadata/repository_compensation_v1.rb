# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class RepositoryCompensationV1 < EventMetadata
      attribute :result_digest, Types::Sha256Digest
      attribute :producer, ReleaseSets::EvidenceProducerV1
      attribute :run_id, Types::Identifier
    end
  end
end
