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
        lifecycle, *links = plan.events
        lifecycle_valid = case lifecycle
                          when Events::CandidateImpactPairScanStartedV2
                            lifecycle.scan_id == command.scan_id && lifecycle.change_set_id == command.change_set_id &&
                              lifecycle.direction == command.direction && lifecycle.markers == values[:markers] &&
                              lifecycle.from_revision == command.from_revision && lifecycle.to_revision == command.to_revision &&
                              lifecycle.page_size == command.page_size
                          when Events::CandidateImpactPairScanSkippedV2
                            lifecycle.scan_id == command.scan_id
                          else
                            false
                          end
        expected_links = {
          "source_registration" => command.source_registration,
          "policy_partition" => command.policy_partition_event,
          "policy_head" => command.policy_head.event
        }
        links_valid = links.length == 3 && links.all? do |link|
          link.is_a?(Events::CandidateImpactPairScanSourceLinkedV1) &&
            link.scan_id == command.scan_id && expected_links[link.role] == link.source
        end
        streams_valid = plan.writes.length == 4 && plan.writes.all? { _1.stream == values[:expected_stream] }
        key(:plan).failure("must contain the exact pair-scan decision and source links") unless
          streams_valid && lifecycle_valid && links_valid
      end
    end
  end
end
