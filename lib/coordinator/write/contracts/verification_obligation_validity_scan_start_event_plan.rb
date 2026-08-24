# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationValidityScanStartEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::StartVerificationObligationValidityScan))
        required(:expected_stream).value(Types.Instance(StreamReference))
        required(:started_at).filled(:string)
      end

      rule(:plan, :command, :expected_stream, :started_at) do
        plan = values[:plan]
        command = values[:command]
        write = plan.writes.sole if plan.writes.length == 1
        event = write&.event
        valid = write&.stream == values[:expected_stream] &&
          event.is_a?(Events::VerificationObligationValidityScanStartedV1) &&
          event.scan_id == command.scan_id &&
          event.change_set_id == command.change_set_id &&
          event.superseding_partition_event == command.superseding_partition_event &&
          event.from_position.zero? && event.to_position == command.source_global_position &&
          event.page_size == 50 && event.rule_version == command.rule_version &&
          event.started_at == values[:started_at]
        key(:plan).failure("must write the exact validity scan start") unless valid
      end
    end
  end
end
