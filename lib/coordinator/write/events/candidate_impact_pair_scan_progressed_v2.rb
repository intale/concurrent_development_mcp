# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactPairScanProgressedV2 < Base
      contract type: "CandidateImpactPairScanProgressed", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :page_number, Types::Integer.constrained(gteq: 1)
      attribute :next_from_revision, Types::StreamRevision
      attribute :change_set_id, Types::Identifier
      attribute :direction, Types::CandidateImpactQueryDirection
      attribute :markers, Types::CandidateImpactPairScanMarkers
      attribute :to_revision, Types::StreamRevision
      attribute :page_size, Types::CandidateImpactScanPageSize
    end
  end
end
