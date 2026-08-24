# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RepositoryIntegrationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV1))
        required(:command).value(Types.Instance(Commands::RecordRepositoryIntegration))
        required(:observation).maybe(Types.Instance(Events::MergeObservedV1))
        required(:recorded_at).filled(:string)
      end

      rule(:plan, :state, :command, :observation, :recorded_at) do
        expected = Domain::ReleaseSets::RecordRepositoryIntegration.new.call(
          state: values[:state],
          command: values[:command],
          observation: values[:observation],
          recorded_at: values[:recorded_at]
        )
        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve the exact ordered repository integration decision")
        end
      end
    end
  end
end
