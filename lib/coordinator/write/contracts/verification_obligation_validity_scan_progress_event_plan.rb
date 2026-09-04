# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationValidityScanProgressEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationObligationValidityScans::State))
        required(:command).value(Types.Instance(Commands::ProgressVerificationObligationValidityScan))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :state, :command, :expected_stream) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        event = plan.events.first
        valid = plan.writes.one? && plan.writes.first.stream == values[:expected_stream] &&
          event&.scan_id == command.scan_id
        valid &&= if command.has_more
          event.is_a?(Events::VerificationObligationValidityScanProgressedV2) &&
            event.page_number == state.page_count + 1 &&
            event.next_from_position == command.last_processed_position + 1 &&
            event.change_set_id == state.change_set_id && event.page_size == state.page_size
        else
          event.is_a?(Events::VerificationObligationValidityScanCompletedV2)
        end
        key(:plan).failure("must contain one exact validity-scan progress or completion fact") unless valid
      end
    end
  end
end
