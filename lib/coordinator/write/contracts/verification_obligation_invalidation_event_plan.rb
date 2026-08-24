# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationInvalidationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationObligationInvalidations::State))
        required(:command).value(Types.Instance(Commands::InvalidateVerificationObligation))
        required(:invalidation_digest).filled(:string)
        required(:invalidated_at).filled(:string)
      end

      rule(:plan, :state, :command, :invalidation_digest, :invalidated_at) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        write = plan.writes.sole if plan.writes.length == 1
        event = write&.event
        valid = write&.stream == StreamFactory.new.verification_obligation(command.obligation_id) &&
          event.is_a?(Events::VerificationObligationInvalidatedV1) &&
          event.obligation_id == command.obligation_id && event.obligation_event == state.obligation_event &&
          event.invalidated_policy == state.obligation.policy &&
          event.superseding_partition_event == command.superseding_partition_event &&
          event.previous_status == state.status && event.previous_terminal_event == state.previous_terminal_event &&
          event.reason == "policy_partition_advanced" &&
          event.invalidation_digest == values[:invalidation_digest] &&
          event.rule_version == command.rule_version && event.invalidated_at == values[:invalidated_at]
        key(:plan).failure("must write the exact invalidation fact") unless valid
      end
    end
  end
end
