# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class MergeObservationV2 < EventMetadata
      attribute :authorization_decision_digest, Types::Sha256Digest
      attribute :observation_digest, Types::Sha256Digest
    end
  end
end
