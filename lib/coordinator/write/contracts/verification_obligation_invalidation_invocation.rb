# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationInvalidationInvocation < Dry::Validation::Contract
      include ProcessStepCausation

      params do
        required(:invocation).value(Types.Instance(Coordinator::Write::VerificationObligationInvalidationInvocation))
      end

      rule(:invocation) do
        invocation = values[:invocation]
        command = invocation.command
        failures = []
        failures << "causation event must match its exact reference" unless physical_reference(invocation.caused_by_event) == invocation.caused_by_reference
        failures << "command ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.command_id)
        failures << "causal parent must be the ProcessStep that allocated the invalidation command" unless process_step_matches?(invocation.caused_by_event, command_id: command.command_id)
        failures << "actor must be the validity policy" unless command.actor.kind == "system" && command.actor.id == "verification-obligation-validity-policy"
        failures << "obligation stream identity must match" unless obligation_reference?(command)
        failures.each { key(:invocation).failure(_1) }
      end

      private

      def obligation_reference?(command)
        reference = command.obligation_event
        reference.type == "VerificationObligationCreated" &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == command.obligation_id &&
          reference.stream_revision.zero?
      end

      def physical_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
