# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class ActivationPointV1 < Value
      attribute :kind, Types::ReleaseSetActivationPointKind
      attribute :environment, Types::Identifier
      attribute :external_reference, Types::ReleaseSetExternalReference
      attribute :state_digest, Types::Sha256Digest
      attribute :producer, EvidenceProducerV1
      attribute :run_id, Types::Identifier
      attribute :activated_at, Types::Timestamp
    end
  end
end
