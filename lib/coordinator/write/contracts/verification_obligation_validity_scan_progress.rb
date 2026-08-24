# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationValidityScanProgress < Dry::Validation::Contract
      params do
        required(:invocation).value(Types.Instance(VerificationObligationValidityScanProgressInvocation))
        required(:expected_identity).filled(:string)
      end

      rule(:invocation, :expected_identity) do
        invocation = values[:invocation]
        command = invocation.command
        failures = []
        failures << "checkpoint must be the exact physical event" unless physical_reference(invocation.checkpoint_event) == invocation.checkpoint_reference
        failures << "command checkpoint must match the invocation" unless command.expected_checkpoint == invocation.checkpoint_reference
        failures << "command ID must match the canonical checkpoint identity" unless command.command_id == values[:expected_identity]
        failures << "actor must be the validity policy" unless command.actor.kind == "system" && command.actor.id == "verification-obligation-validity-policy"
        failures << "page size must be 50" unless command.page_size == 50
        failures << "page result is incoherent" unless coherent_page?(command)
        failures.each { key(:invocation).failure(_1) }
      end

      private

      def coherent_page?(command)
        count = command.page_obligation_count
        last = command.last_processed_position
        return count.zero? && !command.has_more unless last

        count.positive? && (!command.has_more || count == command.page_size)
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
