# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class PairScanSnapshot < Value
      attribute :state, Types.Instance(Domain::CandidateObligationScans::PairScanState)
      attribute :latest_revision, Types::StreamRevision.optional
      attribute :persisted_events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 4)
    end
  end
end
