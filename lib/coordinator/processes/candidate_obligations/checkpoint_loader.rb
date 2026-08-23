# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class CheckpointLoader
      def initialize(
        event_store:,
        registry_loader: Coordinator::Write::CandidateObligationScans::RegistrySweepLoader.new(event_store:),
        pair_loader: Coordinator::Write::CandidateObligationScans::PairScanLoader.new(event_store:),
        registry_contract: Contracts::CandidateImpactRegistrySweepCheckpoint.new,
        pair_contract: Contracts::CandidateImpactPairScanCheckpoint.new
      )
        @registry_loader = registry_loader
        @pair_loader = pair_loader
        @registry_contract = registry_contract
        @pair_contract = pair_contract
      end

      def registry(source)
        state = @registry_loader.call(source.reference.stream_id).state
        return if state.terminal?
        return unless state.checkpoint_event == source.reference

        verify!(@registry_contract, state, source)
        RegistrySweepCheckpointV1.new(event: source.event, reference: source.reference, state:)
      end

      def pair(source)
        state = @pair_loader.call(source.reference.stream_id).state
        return if state.terminal?
        return unless state.checkpoint_event == source.reference

        verify!(@pair_contract, state, source)
        PairScanCheckpointV1.new(event: source.event, reference: source.reference, state:)
      end

      private

      def verify!(contract, state, source)
        result = contract.call(state:, source:)
        return if result.success?

        raise CandidateObligationProcessRejected,
              "Candidate impact scan checkpoint is invalid: #{result.errors.to_h.inspect}"
      end
    end
  end
end
