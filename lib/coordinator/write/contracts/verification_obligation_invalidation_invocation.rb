# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationInvalidationInvocation < Dry::Validation::Contract
      params do
        required(:invocation).value(Types.Instance(Coordinator::Write::VerificationObligationInvalidationInvocation))
        required(:expected_identity).filled(:string)
      end

      rule(:invocation, :expected_identity) do
        invocation = values[:invocation]
        command = invocation.command
        failures = []
        failures << "causation event must match its exact reference" unless physical_reference(invocation.caused_by_event) == invocation.caused_by_reference
        failures << "command and canonical identities must match" unless command.command_id == values[:expected_identity]
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
