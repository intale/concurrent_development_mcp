# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetVerificationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV2))
        required(:command).value(Types.Instance(Commands::RecordReleaseSetVerification))
      end

      rule(:plan, :state, :command) do
        expected = Domain::ReleaseSets::RecordVerification.new.call(
          state: values[:state],
          command: values[:command]
        )
        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve the exact composite verification decision")
        end
      end
    end
  end
end
