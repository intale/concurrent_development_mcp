# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactPairScanProgressEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ProgressCandidateImpactPairScan))
        required(:state).value(Types.Instance(Domain::CandidateObligationScans::PairScanState))
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
          event.is_a?(Events::CandidateImpactPairScanProgressedV2) &&
            event.page_number == state.page_count + 1 &&
            event.next_from_revision == command.last_processed_revision + 1 &&
            event.change_set_id == state.change_set_id && event.direction == state.direction &&
            event.markers == state.markers && event.to_revision == state.to_revision &&
            event.page_size == state.page_size
        else
          event.is_a?(Events::CandidateImpactPairScanCompletedV2)
        end
        key(:plan).failure("must contain one exact pair-scan progress or completion fact") unless valid
      end
    end
  end
end
