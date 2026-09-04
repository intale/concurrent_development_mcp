# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactPairScanStartedV2 < Base
      contract type: "CandidateImpactPairScanStarted", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :direction, Types::CandidateImpactQueryDirection
      attribute :markers, Types::CandidateImpactPairScanMarkers
      attribute :from_revision, Types::StreamRevision
      attribute :to_revision, Types::StreamRevision
      attribute :page_size, Types::CandidateImpactScanPageSize
    end
  end
end
