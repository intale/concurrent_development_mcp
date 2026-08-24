# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class ProducerV1 < Value
      attribute :name, Types::VerificationEvidenceProducerName
      attribute :version, Types::VerificationEvidenceProducerVersion
    end
  end
end
