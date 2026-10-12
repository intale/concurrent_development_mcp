# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class State < Value
      Creation = Types.Instance(Events::OperationBatchCreatedV2)
      TargetSelection = Types.Instance(Events::OperationBatchTargetSelectedV1)
      Outcome = Types.Instance(Events::OperationBatchItemSucceededV2) |
                Types.Instance(Events::OptimisticSagas::OperationBatchItemFailedV1) |
                Types.Instance(Events::OperationBatchItemRejectedV2) |
                Types.Instance(Events::OperationBatchItemRegistrationRejectedV1)
      CompletionLink = Types.Instance(Events::OperationBatchItemCompletionLinkedV1)
      Cancellation = Types.Instance(Events::OperationBatchCancellationRequestedV2)
      Terminal = Types.Instance(Events::OperationBatchCompletedV2) |
                 Types.Instance(Events::OperationBatchCancelledV2)

      attribute :creation, Creation.optional
      attribute :target_selection, TargetSelection.optional
      attribute :items, Types::Array.of(ItemV2 | ItemIdentityV1)
      attribute :item_count, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS).optional
      attribute :assignments, Types::Array.of(Events::OperationBatchItemCommandAssignedV1)
      attribute :starts, Types::Array.of(Events::OperationBatchItemExecutionStartedV1)
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
          item_count: 0,
          assignments: [],
          starts: [],
          page_size: nil,
          outcomes: [],
          completion_links: [],
          cancellation: nil,
          terminal: nil
        )
      end

      def self.reduce(events, items: [], page_size: nil, item_count: items.length)
        creation = nil
        target_selection = nil
        outcomes = []
        assignments = []
        starts = []
        completion_links = []
        cancellation = nil
        terminal = nil

        events.each do |event|
          case event
          when Events::OperationBatchCreatedV2 then creation = event
          when Events::OperationBatchTargetSelectedV1 then target_selection = event
          when Events::OperationBatchItemCommandAssignedV1 then assignments << event
          when Events::OperationBatchItemExecutionStartedV1 then starts << event
          when Events::OperationBatchItemSucceededV2, Events::OperationBatchItemRejectedV2,
               Events::OptimisticSagas::OperationBatchItemFailedV1,
               Events::OperationBatchItemRegistrationRejectedV1
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
          item_count:,
          assignments:,
          starts:,
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

      def assignment(index)
        assignments.find { _1.index == index }
      end

      def started?(index)
        starts.any? { _1.index == index }
      end

      def started_pending_indexes
        completed = outcomes.to_h { [ _1.index, true ] }
        starts.map(&:index).reject { completed.key?(_1) }
      end

      def pending_indexes
        return [] unless creation

        count = item_count || raise(InvalidOperationBatchHistory, "Manifest count was not loaded for progress")
        completed = outcomes.to_h { [ _1.index, true ] }
        (0...count).reject { completed.key?(_1) }
      end

      def succeeded_count
        outcomes.count { _1.is_a?(Events::OperationBatchItemSucceededV2) }
      end

      def rejected_count
        outcomes.count do |event|
          event.is_a?(Events::OperationBatchItemRejectedV2) ||
            event.is_a?(Events::OptimisticSagas::OperationBatchItemFailedV1) ||
            event.is_a?(Events::OperationBatchItemRegistrationRejectedV1)
        end
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
