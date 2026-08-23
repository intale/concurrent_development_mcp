# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class ScanCheckpointLoader
      def initialize(
        event_store:,
        loader: Coordinator::Write::AgentChoiceImpacts::ScanLoader.new(event_store:),
        contract: Contracts::AgentChoiceImpactScanCheckpointSource.new
      )
        @loader = loader
        @contract = contract
      end

      def call(source)
        state = @loader.call(source.reference.stream_id).state
        return if state.terminal?
        return if state.running? && state.checkpoint_event != source.reference

        verify!(state, source)
        ScanCheckpointV1.new(
          event: source.event,
          reference: source.reference,
          scan_id: state.scan_id,
          decision_change: state.decision_change,
          from_position: state.from_position,
          to_position: state.to_position,
          page_size: state.page_size,
          policy_version: state.policy_version
        )
      rescue Dry::Struct::Error => error
        raise AgentChoiceImpactProcessRejected, error.message
      end

      private

      def verify!(state, source)
        result = @contract.call(state:, source:)
        return if result.success?

        raise AgentChoiceImpactProcessRejected,
              "AgentChoice impact checkpoint is invalid: #{result.errors.to_h.inspect}"
      end
    end
  end
end
