# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactRegistrySweepStart < Dry::Validation::Contract
      include ProcessStepCausation

      params do
        required(:invocation).value(Types.Instance(CandidateImpactRegistrySweepInvocation))
      end

      rule(:invocation) do
        invocation = values[:invocation]
        command = invocation.command
        failures = []
        failures << "source reference must be the policy partition event" unless invocation.source_reference == command.policy_partition_event
        failures << "source event must be the exact supplied reference" unless physical_reference(invocation.source_event) == invocation.source_reference
        failures << "scan ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.scan_id)
        failures << "command ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.command_id)
        unless process_step_matches?(invocation.caused_by, command_id: command.command_id, target_entity_id: command.scan_id)
          failures << "causal parent must be the ProcessStep that allocated the scan command and identity"
        end
        failures << "actor must be the candidate-impact obligation policy" unless command.actor.kind == "system" && command.actor.id == "candidate-impact-obligation-policy"
        failures << "cursor and page size must be the version-1 constants" unless command.from_revision.zero? && command.page_size == 50
        failures.each { key(:invocation).failure(_1) }
      end

      private

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
