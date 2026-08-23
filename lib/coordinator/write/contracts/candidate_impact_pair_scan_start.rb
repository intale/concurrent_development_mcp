# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactPairScanStart < Dry::Validation::Contract
      params do
        required(:invocation).value(Types.Instance(CandidateImpactPairScanInvocation))
        required(:evidence).value(Types.Instance(CandidateObligations::CandidateEvidenceV1))
        required(:expected_identity).filled(:string)
      end

      rule(:invocation, :evidence, :expected_identity) do
        invocation = values[:invocation]
        command = invocation.command
        evidence = values[:evidence]
        failures = []
        failures << "source event must be the exact supplied reference" unless physical_reference(invocation.source_event) == invocation.source_reference
        failures << "scan and command IDs must match the canonical identity" unless command.scan_id == values[:expected_identity] && command.command_id == values[:expected_identity]
        failures << "actor must be the candidate-impact obligation policy" unless command.actor.kind == "system" && command.actor.id == "candidate-impact-obligation-policy"
        failures << "registration must match exact Candidate evidence" unless command.source_registration == evidence.registration_event
        failures << "ChangeSet must match exact Candidate evidence" unless command.change_set_id == evidence.subject.change_set_id
        failures << "revision bounds must select predecessors only" unless command.from_revision.zero? && command.to_revision == command.source_registration.stream_revision - 1
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
