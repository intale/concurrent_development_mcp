# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetCompensatedCompletionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV1))
        required(:command).value(Types.Instance(Commands::CompleteCompensatedReleaseSet))
        required(:completed_at).filled(:string)
      end

      rule(:plan, :state, :command, :completed_at) do
        expected = Domain::ReleaseSets::CompleteCompensated.new.call(
          state: values[:state], command: values[:command], completed_at: values[:completed_at]
        )
        key(:plan).failure("must preserve the exact compensated completion decision") unless expected.success? && values[:plan] == expected.value!
      end
    end
  end
end
