# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeObservationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:history).value(Types.Instance(Domain::MergeObservations::HistoryV1))
        required(:command).value(Types.Instance(Commands::RecordMergeObservation))
        required(:observation_digest).filled(:string)
        required(:recorded_at).filled(:string)
      end

      rule(:plan, :history, :command, :observation_digest, :recorded_at) do
        expected = Domain::MergeObservations::Record.new.call(
          history: values[:history],
          command: values[:command],
          observation_digest: values[:observation_digest],
          recorded_at: values[:recorded_at]
        )
        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve the exact authorized external observation")
        end
      end
    end
  end
end
