# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetPreparationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::PreparationStateV1))
        required(:command).value(Types.Instance(Commands::PrepareReleaseSet))
        required(:prepared_at).filled(:string)
      end

      rule(:plan, :state, :command, :prepared_at) do
        expected = Domain::ReleaseSets::Prepare.new.call(
          state: values[:state],
          command: values[:command],
          prepared_at: values[:prepared_at]
        )
        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve exact current ReleaseSet preparation evidence")
        end
      end
    end
  end
end
