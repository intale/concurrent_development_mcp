# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationInvalidationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationObligationInvalidations::State))
        required(:command).value(Types.Instance(Commands::InvalidateVerificationObligation))
      end

      rule(:plan, :state, :command) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        write = plan.writes.sole if plan.writes.length == 1
        event = write&.event
        valid = write&.stream == StreamFactory.new.verification_obligation(command.obligation_id) &&
          event.is_a?(Events::VerificationObligationInvalidatedV2) &&
          event.obligation_id == command.obligation_id &&
          event.superseding_partition_event == command.superseding_partition_event &&
          event.reason == "policy_partition_advanced"
        key(:plan).failure("must write the exact invalidation fact") unless valid
      end
    end
  end
end
