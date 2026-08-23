# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class CandidateImpactRegistrySweepCheckpoint < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Coordinator::Write::Domain::CandidateObligationScans::RegistrySweepState))
        required(:source).value(Types.Instance(CandidateObligations::SourceV1))
      end

      rule(:state, :source) do
        state = values[:state]
        source = values[:source]
        valid = state.running? &&
                state.checkpoint_event == source.reference &&
                state.scan_id == source.reference.stream_id &&
                %w[CandidateImpactRegistrySweepStarted CandidateImpactRegistrySweepProgressed].include?(source.reference.type)
        key(:state).failure("must identify the current running registry-sweep checkpoint") unless valid
      end
    end
  end
end
