# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class AgentChoiceImpactPage < Dry::Validation::Contract
      params do
        required(:page).value(Types.Instance(AgentChoiceImpacts::PageV1))
        required(:checkpoint).value(Types.Instance(AgentChoiceImpacts::ScanCheckpointV1))
      end

      rule(:page, :checkpoint) do
        page = values[:page]
        checkpoint = values[:checkpoint]
        events = page.accepted_choices
        positions = events.map(&:global_position)
        target_markers = checkpoint.decision_change.affected_partitions.map do
          "decision-partition:#{_1.partition_id}"
        end
        valid_events = events.all? do |event|
          event.type == "AgentChoiceAccepted" &&
            event.stream&.context == "AgentGovernance" &&
            event.stream&.stream_name == "AgentChoice" &&
            event.stream_revision == 1 &&
            event.global_position&.between?(checkpoint.from_position, checkpoint.to_position) &&
            (event.markers & target_markers).any?
        end
        exact_cursor = page.last_processed_position == positions.last
        bounded_more = page.has_more ? events.length == checkpoint.page_size : events.length <= checkpoint.page_size
        unique_and_ordered = events.map(&:id).uniq.length == events.length && positions == positions.sort

        key(:page).failure("must contain exact ordered accepted Choice targets") unless valid_events && unique_and_ordered
        key(:page).failure("must expose the exact processed cursor and sentinel result") unless exact_cursor && bounded_more
      end
    end
  end
end
