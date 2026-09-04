# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeObservationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:history).value(Types.Instance(Domain::MergeObservations::HistoryV1))
        required(:command).value(Types.Instance(Commands::RecordMergeObservation))
      end

      rule(:plan, :history, :command) do
        expected = Domain::MergeObservations::Record.new.call(
          history: values[:history],
          command: values[:command]
        )
        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve the exact authorized external observation")
        end
      end
    end
  end
end
