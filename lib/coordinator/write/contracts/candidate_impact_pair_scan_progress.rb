# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactPairScanProgress < Dry::Validation::Contract
      include ProcessStepCausation

      params do
        required(:invocation).value(Types.Instance(CandidateImpactPairScanProgressInvocation))
      end

      rule(:invocation) do
        invocation = values[:invocation]
        command = invocation.command
        failures = []
        failures << "checkpoint event must be the exact supplied reference" unless physical_reference(invocation.checkpoint_event) == invocation.checkpoint_reference
        failures << "command checkpoint must match the invocation" unless command.expected_checkpoint == invocation.checkpoint_reference
        failures << "command ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.command_id)
        failures << "causal parent must be the ProcessStep that allocated the progress command" unless process_step_matches?(invocation.caused_by, command_id: command.command_id)
        failures << "actor must be the candidate-impact obligation policy" unless command.actor.kind == "system" && command.actor.id == "candidate-impact-obligation-policy"
        failures << "page and index policy versions must be version-1 constants" unless command.page_size == 50 && command.index_policy_version == Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION
        failures << "page result is incoherent" unless coherent_page?(command)
        failures.each { key(:invocation).failure(_1) }
      end

      private

      def coherent_page?(command)
        count = command.page_registration_count
        last = command.last_processed_revision
        return count.zero? && !command.has_more unless last

        count <= command.page_size
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
