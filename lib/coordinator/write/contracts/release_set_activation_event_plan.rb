# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetActivationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV1))
        required(:command).value(Types.Instance(Commands::RecordReleaseSetActivation))
        required(:recorded_at).filled(:string)
      end

      rule(:plan, :state, :command, :recorded_at) do
        expected = Domain::ReleaseSets::RecordActivation.new.call(
          state: values[:state], command: values[:command], recorded_at: values[:recorded_at]
        )
        key(:plan).failure("must preserve the exact activation decision") unless expected.success? && values[:plan] == expected.value!
      end
    end
  end
end
