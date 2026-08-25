# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class State < Value
      Creation = Types.Instance(Events::OperationBatchCreatedV1)
      Outcome = Types.Instance(Events::OperationBatchItemSucceededV1) |
                Types.Instance(Events::OperationBatchItemRejectedV1)
      Cancellation = Types.Instance(Events::OperationBatchCancellationRequestedV1)
      Terminal = Types.Instance(Events::OperationBatchCompletedV1) |
                 Types.Instance(Events::OperationBatchCancelledV1)

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
          when Events::OperationBatchCreatedV1 then creation = event
          when Events::OperationBatchItemSucceededV1, Events::OperationBatchItemRejectedV1
            outcomes << event
          when Events::OperationBatchCancellationRequestedV1 then cancellation = event
          when Events::OperationBatchCompletedV1, Events::OperationBatchCancelledV1
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
        outcomes.count { _1.is_a?(Events::OperationBatchItemSucceededV1) }
      end

      def rejected_count
        outcomes.count { _1.is_a?(Events::OperationBatchItemRejectedV1) }
      end

      def running?
        !creation.nil? && terminal.nil?
      end
    end
  end
end
