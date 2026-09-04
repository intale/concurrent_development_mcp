# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetActivatedCompletionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV2))
        required(:command).value(Types.Instance(Commands::CompleteActivatedReleaseSet))
      end

      rule(:plan, :state, :command) do
        expected = Domain::ReleaseSets::CompleteActivated.new.call(
          state: values[:state], command: values[:command]
        )
        key(:plan).failure("must preserve the exact activated completion decision") unless expected.success? && values[:plan] == expected.value!
      end
    end
  end
end
