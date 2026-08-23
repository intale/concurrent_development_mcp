# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class CandidateImpactPairScanCheckpoint < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Coordinator::Write::Domain::CandidateObligationScans::PairScanState))
        required(:source).value(Types.Instance(CandidateObligations::SourceV1))
      end

      rule(:state, :source) do
        state = values[:state]
        source = values[:source]
        valid = state.running? &&
                state.checkpoint_event == source.reference &&
                state.scan_id == source.reference.stream_id &&
                %w[CandidateImpactPairScanStarted CandidateImpactPairScanProgressed].include?(source.reference.type)
        key(:state).failure("must identify the current running pair-scan checkpoint") unless valid
      end
    end
  end
end
