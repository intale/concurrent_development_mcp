# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class State < Value
      Creation = Types.Instance(Events::OperationBatchCreatedV2)
      TargetSelection = Types.Instance(Events::OperationBatchTargetSelectedV1)
      Outcome = Types.Instance(Events::OperationBatchItemSucceededV2) |
                Types.Instance(Events::OperationBatchItemRejectedV2)
      CompletionLink = Types.Instance(Events::OperationBatchItemCompletionLinkedV1)
      Cancellation = Types.Instance(Events::OperationBatchCancellationRequestedV2)
      Terminal = Types.Instance(Events::OperationBatchCompletedV2) |
                 Types.Instance(Events::OperationBatchCancelledV2)

      attribute :creation, Creation.optional
      attribute :target_selection, TargetSelection.optional
      attribute :items, Types::Array.of(ItemV2)
      attribute :page_size, Types::OperationBatchPageSize.optional
      attribute :outcomes, Types::Array.of(Outcome)
      attribute :completion_links, Types::Array.of(CompletionLink)
      attribute :cancellation, Cancellation.optional
      attribute :terminal, Terminal.optional

      def self.initial
        new(
          creation: nil,
          target_selection: nil,
          items: [],
          page_size: nil,
          outcomes: [],
          completion_links: [],
          cancellation: nil,
          terminal: nil
        )
      end

      def self.reduce(events, items: [], page_size: nil)
        creation = nil
        target_selection = nil
        outcomes = []
        completion_links = []
        cancellation = nil
        terminal = nil

        events.each do |event|
          case event
          when Events::OperationBatchCreatedV2 then creation = event
          when Events::OperationBatchTargetSelectedV1 then target_selection = event
          when Events::OperationBatchItemSucceededV2, Events::OperationBatchItemRejectedV2
            outcomes << event
          when Events::OperationBatchItemCompletionLinkedV1 then completion_links << event
          when Events::OperationBatchCancellationRequestedV2 then cancellation = event
          when Events::OperationBatchCompletedV2, Events::OperationBatchCancelledV2
            terminal = event
          end
        end

        new(
          creation:,
          target_selection:,
          items: items.sort_by(&:index),
          page_size:,
          outcomes:,
          completion_links:,
          cancellation:,
          terminal:
        )
      end

      def item(index)
        items.find { _1.index == index }
      end

      def outcome(index)
        outcomes.find { _1.index == index }
      end

      def pending_indexes
        return [] unless creation

        completed = outcomes.map(&:index)
        items.map(&:index).reject { completed.include?(_1) }
      end

      def succeeded_count
        outcomes.count { _1.is_a?(Events::OperationBatchItemSucceededV2) }
      end

      def rejected_count
        outcomes.count { _1.is_a?(Events::OperationBatchItemRejectedV2) }
      end

      def running?
        !creation.nil? && terminal.nil?
      end

      def processing_page_size
        page_size || raise(InvalidOperationBatchHistory, "Batch creation has no page-size metadata")
      end
    end
  end
end
