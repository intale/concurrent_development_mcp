# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class State < Value
      Creation = Types.Instance(Events::OperationBatchCreatedV2)
      Outcome = Types.Instance(Events::OperationBatchItemSucceededV2) |
                Types.Instance(Events::OperationBatchItemRejectedV2)
      Cancellation = Types.Instance(Events::OperationBatchCancellationRequestedV2)
      Terminal = Types.Instance(Events::OperationBatchCompletedV2) |
                 Types.Instance(Events::OperationBatchCancelledV2)

      attribute :creation, Creation.optional
      attribute :outcomes, Types::Array.of(Outcome)
      attribute :cancellation, Cancellation.optional
      attribute :terminal, Terminal.optional

      def self.initial
        new(creation: nil, outcomes: [], cancellation: nil, terminal: nil)
      end

      def self.reduce(events)
        creation = nil
        outcomes = []
        cancellation = nil
        terminal = nil

        events.each do |event|
          case event
          when Events::OperationBatchCreatedV2 then creation = event
          when Events::OperationBatchItemSucceededV2, Events::OperationBatchItemRejectedV2
            outcomes << event
          when Events::OperationBatchCancellationRequestedV2 then cancellation = event
          when Events::OperationBatchCompletedV2, Events::OperationBatchCancelledV2
            terminal = event
          end
        end

        new(creation:, outcomes:, cancellation:, terminal:)
      end

      def item(index)
        creation&.items&.find { _1.index == index }
      end

      def outcome(index)
        outcomes.find { _1.index == index }
      end

      def pending_indexes
        return [] unless creation

        completed = outcomes.map(&:index)
        creation.items.map(&:index).reject { completed.include?(_1) }
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
    end
  end
end
