# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class PairScanCheckpointV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, Coordinator::Write::EventReference
      attribute :state, Types.Instance(Coordinator::Write::Domain::CandidateObligationScans::PairScanState)
    end
  end
end
