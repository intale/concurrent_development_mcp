# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactRegistrySweepStartEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::StartCandidateImpactRegistrySweep))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        unless plan.writes.length == 1 && plan.writes.first.stream == values[:expected_stream]
          key(:plan).failure("must contain one write to the registry-sweep stream")
          next
        end

        event = plan.writes.first.event
        allowed = event.is_a?(Events::CandidateImpactRegistrySweepStartedV1) ||
                  event.is_a?(Events::CandidateImpactRegistrySweepSkippedV1)
        common = allowed && event.scan_id == command.scan_id &&
                 event.change_set_id == command.change_set_id &&
                 event.policy_partition_event == command.policy_partition_event &&
                 event.policy_head == command.policy_head &&
                 event.from_revision == command.from_revision &&
                 event.page_size == command.page_size &&
                 event.rule_version == command.rule_version
        key(:plan).failure("event must retain the exact registry-sweep command evidence") unless common
      end
    end
  end
end
