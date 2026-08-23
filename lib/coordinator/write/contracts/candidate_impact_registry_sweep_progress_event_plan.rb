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
        unless plan.writes.length == 1 && plan.writes.first.stream == values[:expected_stream]
          key(:plan).failure("must contain one write to the registry-sweep stream")
          next
        end

        event = plan.writes.first.event
        expected_class = command.has_more ? Events::CandidateImpactRegistrySweepProgressedV1 : Events::CandidateImpactRegistrySweepCompletedV1
        common = event.is_a?(expected_class) && event.scan_id == command.scan_id &&
                 event.policy_partition_event == command.policy_partition_event &&
                 event.policy_head == command.policy_head &&
                 event.started_event == state.started_event &&
                 event.previous_checkpoint == command.expected_checkpoint &&
                 event.previous_from_revision == command.previous_from_revision &&
                 event.to_revision == state.to_revision &&
                 event.page_registration_count == command.page_registration_count &&
                 event.rule_version == command.rule_version
        key(:plan).failure("event must retain the exact registry-sweep checkpoint evidence") unless common
      end
    end
  end
end
