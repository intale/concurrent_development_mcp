# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateImpactScanContextV1 < Value
      attribute :target_stream, Types.Instance(StreamReference)
      attribute :scan_id, Types::UuidV7
      attribute :change_set_id, Types::UuidV7
      attribute? :source_registration, EventReference.optional.default(nil)
      attribute :policy_partition, EventReference
      attribute :policy_head, EventReference
      attribute :decision_id, Types::UuidV7
      attribute :routing_markers,
                Types::Array.of(Types::Marker).constrained(max_size: 32).default([].freeze)
    end
  end
end
