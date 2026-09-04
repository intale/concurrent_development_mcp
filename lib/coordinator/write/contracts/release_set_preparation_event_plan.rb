# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetPreparationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::PreparationStateV1))
        required(:command).value(Types.Instance(Commands::PrepareReleaseSet))
      end

      rule(:plan, :state, :command) do
        expected = Domain::ReleaseSets::Prepare.new.call(
          state: values[:state],
          command: values[:command]
        )
        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve exact current ReleaseSet preparation evidence")
        end
      end
    end
  end
end
