# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetVerificationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV1))
        required(:command).value(Types.Instance(Commands::RecordReleaseSetVerification))
        required(:recorded_at).filled(:string)
      end

      rule(:plan, :state, :command, :recorded_at) do
        expected = Domain::ReleaseSets::RecordVerification.new.call(
          state: values[:state],
          command: values[:command],
          recorded_at: values[:recorded_at]
        )
        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve the exact composite verification decision")
        end
      end
    end
  end
end
