# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetActivationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV2))
        required(:command).value(Types.Instance(Commands::RecordReleaseSetActivation))
      end

      rule(:plan, :state, :command) do
        expected = Domain::ReleaseSets::RecordActivation.new.call(
          state: values[:state], command: values[:command]
        )
        key(:plan).failure("must preserve the exact activation decision") unless expected.success? && values[:plan] == expected.value!
      end
    end
  end
end
