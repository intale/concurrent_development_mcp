# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactPairScanStartEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::StartCandidateImpactPairScan))
        required(:markers).array(Types::Marker)
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :markers, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        unless plan.writes.length == 1 && plan.writes.first.stream == values[:expected_stream]
          key(:plan).failure("must contain one write to the pair-scan stream")
          next
        end

        event = plan.writes.first.event
        allowed = event.is_a?(Events::CandidateImpactPairScanStartedV1) ||
                  event.is_a?(Events::CandidateImpactPairScanSkippedV1)
        common = allowed && event.scan_id == command.scan_id &&
                 event.change_set_id == command.change_set_id &&
                 event.source_registration == command.source_registration &&
                 event.direction == command.direction &&
                 event.policy_partition_event == command.policy_partition_event &&
                 event.policy_head == command.policy_head &&
                 event.markers == values[:markers] &&
                 event.from_revision == command.from_revision &&
                 event.to_revision == command.to_revision &&
                 event.page_size == command.page_size &&
                 event.index_policy_version == command.index_policy_version &&
                 event.rule_version == command.rule_version
        key(:plan).failure("event must retain the exact pair-scan command evidence") unless common
      end
    end
  end
end
