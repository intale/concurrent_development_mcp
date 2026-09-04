# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationValidityScanStartEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::StartVerificationObligationValidityScan))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        started, link = plan.events
        valid = plan.writes.length == 2 && plan.writes.all? { _1.stream == values[:expected_stream] } &&
          started.is_a?(Events::VerificationObligationValidityScanStartedV2) &&
          started.scan_id == command.scan_id && started.change_set_id == command.change_set_id &&
          started.from_position.zero? && started.to_position == command.source_global_position &&
          started.page_size == 50 &&
          link.is_a?(Events::VerificationObligationValidityScanSourceLinkedV1) &&
          link.scan_id == command.scan_id && link.role == "superseding_partition" &&
          link.source == command.superseding_partition_event
        key(:plan).failure("must contain the exact validity-scan start and source link") unless valid
      end
    end
  end
end
