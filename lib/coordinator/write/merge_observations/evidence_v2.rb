# frozen_string_literal: true

module Coordinator::Write
  module MergeObservations
    class EvidenceV2 < Value
      attribute :observation, Events::MergeObservedV2
      attribute :event, EventReference
      attribute :observation_digest, Types::Sha256Digest
      attribute :snapshot, MergeSnapshots::StateV2
    end
  end
end
