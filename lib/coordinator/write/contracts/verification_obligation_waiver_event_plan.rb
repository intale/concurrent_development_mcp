# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationWaiverEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationObligationWaivers::State))
        required(:command).value(Types.Instance(Commands::WaiveVerificationObligation))
        required(:waiver_input_digest).filled(:string)
        required(:waived_at).filled(:string)
      end

      rule(:plan, :state, :command, :waiver_input_digest, :waived_at) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        event = plan.events.first
        expected = Events::VerificationObligationWaivedV1.new(
          obligation_id: command.obligation_id,
          obligation_event: state.obligation_event,
          policy: state.obligation.policy,
          previous_status: state.status,
          previous_terminal_event: state.previous_terminal_event,
          reason: command.reason,
          waiver_input_digest: values[:waiver_input_digest],
          waived_at: values[:waived_at]
        )
        valid = plan.writes.length == 1 &&
          plan.writes.first.stream == StreamFactory.new.verification_obligation(command.obligation_id) &&
          event == expected
        key(:plan).failure("must contain one coherent VerificationObligation waiver") unless valid
      end
    end
  end
end
