# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactRegistrySweepProgressEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ProgressCandidateImpactRegistrySweep))
        required(:state).value(Types.Instance(Domain::CandidateObligationScans::RegistrySweepState))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :state, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        state = values[:state]
        event = plan.events.first
        valid = plan.writes.one? && plan.writes.first.stream == values[:expected_stream] &&
          event&.scan_id == command.scan_id
        valid &&= if command.has_more
          event.is_a?(Events::CandidateImpactRegistrySweepProgressedV2) &&
            event.page_number == state.page_count + 1 &&
            event.next_from_revision == command.last_processed_revision + 1 &&
            event.change_set_id == state.change_set_id && event.to_revision == state.to_revision &&
            event.page_size == state.page_size
        else
          event.is_a?(Events::CandidateImpactRegistrySweepCompletedV2)
        end
        key(:plan).failure("must contain one exact registry-sweep progress or completion fact") unless valid
      end
    end
  end
end
