# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactRegistrySweepProgressedV2 < Base
      contract type: "CandidateImpactRegistrySweepProgressed", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :page_number, Types::Integer.constrained(gteq: 1)
      attribute :next_from_revision, Types::StreamRevision
      attribute :change_set_id, Types::Identifier
      attribute :to_revision, Types::StreamRevision
      attribute :page_size, Types::CandidateImpactScanPageSize
    end
  end
end
