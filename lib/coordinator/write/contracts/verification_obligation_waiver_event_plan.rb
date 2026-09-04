# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationWaiverEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationObligationWaivers::State))
        required(:command).value(Types.Instance(Commands::WaiveVerificationObligation))
      end

      rule(:plan, :state, :command) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        event = plan.events.first
        expected = Events::VerificationObligationWaivedV2.new(
          obligation_id: command.obligation_id,
          reason: command.reason
        )
        valid = plan.writes.length == 1 &&
          plan.writes.first.stream == StreamFactory.new.verification_obligation(command.obligation_id) &&
          event == expected
        key(:plan).failure("must contain one coherent VerificationObligation waiver") unless valid
      end
    end
  end
end
