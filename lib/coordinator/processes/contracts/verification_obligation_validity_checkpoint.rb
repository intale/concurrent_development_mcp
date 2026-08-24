# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class VerificationObligationValidityCheckpoint < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Coordinator::Write::Domain::VerificationObligationValidityScans::State))
        required(:source).value(Types.Instance(VerificationObligationValidity::SourceV1))
      end

      rule(:state, :source) do
        state = values[:state]
        source = values[:source]
        valid = state.running? && state.checkpoint_event == source.reference &&
          %w[VerificationObligationValidityScanStarted VerificationObligationValidityScanProgressed].include?(source.reference.type) &&
          source.reference.stream_context == "DevelopmentIntegration" &&
          source.reference.stream_name == "VerificationObligationValidityScan" &&
          source.reference.stream_id == state.scan_id
        key(:state).failure("must be the exact current running checkpoint") unless valid
      end
    end
  end
end
