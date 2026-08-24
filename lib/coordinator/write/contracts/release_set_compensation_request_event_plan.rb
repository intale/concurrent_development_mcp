# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseSetCompensationRequestEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::ReleaseSets::LifecycleStateV1))
        required(:command).value(Types.Instance(Commands::RequestReleaseSetCompensation))
        required(:requested_at).filled(:string)
      end

      rule(:plan, :state, :command, :requested_at) do
        expected = Domain::ReleaseSets::RequestCompensation.new.call(
          state: values[:state], command: values[:command], requested_at: values[:requested_at]
        )
        key(:plan).failure("must preserve the exact compensation request decision") unless expected.success? && values[:plan] == expected.value!
      end
    end
  end
end
