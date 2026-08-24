# frozen_string_literal: true

module Coordinator::Processes
  module VerificationObligationValidity
    class CheckpointLoader
      def initialize(
        event_store:,
        loader: Coordinator::Write::VerificationObligationValidityScans::ScanLoader.new(event_store:),
        contract: Contracts::VerificationObligationValidityCheckpoint.new
      )
        @loader = loader
        @contract = contract
      end

      def call(source)
        state = @loader.call(source.reference.stream_id).state
        return if state.terminal?
        return if state.running? && state.checkpoint_event != source.reference

        result = @contract.call(state:, source:)
        unless result.success?
          raise VerificationObligationValidityProcessRejected,
                "Validity scan checkpoint is invalid: #{result.errors.to_h.inspect}"
        end
        ScanCheckpointV1.new(
          event: source.event,
          reference: source.reference,
          scan_id: state.scan_id,
          change_set_id: state.change_set_id,
          superseding_partition_event: state.superseding_partition_event,
          from_position: state.from_position,
          to_position: state.to_position,
          page_size: state.page_size,
          rule_version: state.rule_version
        )
      rescue Dry::Struct::Error => error
        raise VerificationObligationValidityProcessRejected, error.message
      end
    end
  end
end
