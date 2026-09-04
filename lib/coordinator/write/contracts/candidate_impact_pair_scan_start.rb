# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactPairScanStart < Dry::Validation::Contract
      include ProcessStepCausation

      params do
        required(:invocation).value(Types.Instance(CandidateImpactPairScanInvocation))
        required(:evidence).value(Types.Instance(CandidateObligations::CandidateEvidenceV2))
      end

      rule(:invocation, :evidence) do
        invocation = values[:invocation]
        command = invocation.command
        evidence = values[:evidence]
        failures = []
        failures << "source event must be the exact supplied reference" unless physical_reference(invocation.source_event) == invocation.source_reference
        failures << "scan ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.scan_id)
        failures << "command ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.command_id)
        unless process_step_matches?(invocation.caused_by, command_id: command.command_id, target_entity_id: command.scan_id)
          failures << "causal parent must be the ProcessStep that allocated the scan command and identity"
        end
        failures << "actor must be the candidate-impact obligation policy" unless command.actor.kind == "system" && command.actor.id == "candidate-impact-obligation-policy"
        failures << "registration must match exact Candidate evidence" unless command.source_registration == evidence.registration_event
        failures << "ChangeSet must match exact Candidate evidence" unless command.change_set_id == evidence.subject.change_set_id
        unless command.from_revision.zero? && command.to_revision == evidence.registration_global_position - 1
          failures << "position bounds must select registrations preceding the source"
        end
        failures << "page and index policy versions must be version-1 constants" unless command.page_size == 50 && command.index_policy_version == Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION
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
