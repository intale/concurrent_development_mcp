# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class PageReader
      def initialize(
        event_store:,
        contract: Contracts::AgentChoiceImpactPage.new
      )
        @event_store = event_store
        @contract = contract
      end

      def call(checkpoint)
        rows = @event_store.read_global_marked_page(criteria(checkpoint))
        targets = rows.first(checkpoint.page_size)
        page = PageV1.new(
          accepted_choices: targets,
          last_processed_position: targets.last&.global_position,
          has_more: rows.length > checkpoint.page_size
        )
        verify!(page, checkpoint)
        page
      rescue Dry::Struct::Error => error
        raise AgentChoiceImpactProcessRejected, error.message
      end

      private

      def criteria(checkpoint)
        Coordinator::Write::GlobalMarkedEventPageCriteria.new(
          stream_context: "AgentGovernance",
          stream_name: "AgentChoice",
          event_type: "AgentChoiceAccepted",
          markers: checkpoint.decision_change.affected_partitions.map do
            "decision-partition:#{_1.partition_id}"
          end,
          from_position: checkpoint.from_position,
          to_position: checkpoint.to_position,
          page_size: checkpoint.page_size,
          direction: :asc
        )
      end

      def verify!(page, checkpoint)
        result = @contract.call(page:, checkpoint:)
        return if result.success?

        raise AgentChoiceImpactProcessRejected,
              "AgentChoice impact page is invalid: #{result.errors.to_h.inspect}"
      end
    end
  end
end
