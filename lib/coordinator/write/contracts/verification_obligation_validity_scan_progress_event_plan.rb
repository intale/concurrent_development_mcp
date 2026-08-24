# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationValidityScanProgressEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationObligationValidityScans::State))
        required(:command).value(Types.Instance(Commands::ProgressVerificationObligationValidityScan))
        required(:expected_stream).value(Types.Instance(StreamReference))
        required(:progressed_at).filled(:string)
      end

      rule(:plan, :state, :command, :expected_stream, :progressed_at) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        write = plan.writes.sole if plan.writes.length == 1
        event = write&.event
        valid = write&.stream == values[:expected_stream] && common?(event, state, command)
        valid &&= if command.has_more
          progressed?(event, state, command, values[:progressed_at])
        else
          completed?(event, state, command, values[:progressed_at])
        end
        key(:plan).failure("must write the exact validity scan checkpoint") unless valid
      end

      private

      def common?(event, state, command)
        event && event.scan_id == command.scan_id &&
          event.change_set_id == command.change_set_id &&
          event.superseding_partition_event == command.superseding_partition_event &&
          event.started_event == state.started_event &&
          event.previous_checkpoint == state.checkpoint_event &&
          event.previous_from_position == command.previous_from_position &&
          event.page_size == command.page_size &&
          event.page_obligation_count == command.page_obligation_count &&
          event.total_obligation_count == state.total_obligation_count + command.page_obligation_count &&
          event.rule_version == command.rule_version
      end

      def progressed?(event, state, command, progressed_at)
        event.is_a?(Events::VerificationObligationValidityScanProgressedV1) &&
          event.next_from_position == command.last_processed_position + 1 &&
          event.page_number == state.page_count + 1 &&
          event.progressed_at == progressed_at
      end

      def completed?(event, state, command, progressed_at)
        next_position = command.last_processed_position ?
          command.last_processed_position + 1 : command.previous_from_position
        event.is_a?(Events::VerificationObligationValidityScanCompletedV1) &&
          event.final_from_position == next_position &&
          event.page_count == state.page_count + 1 &&
          event.completed_at == progressed_at
      end
    end
  end
end
