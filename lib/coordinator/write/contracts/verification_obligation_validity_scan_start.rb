# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationValidityScanStart < Dry::Validation::Contract
      params do
        required(:invocation).value(Types.Instance(VerificationObligationValidityScanInvocation))
        required(:source).value(Types.Instance(CandidateObligations::PersistedEventV1))
        required(:expected_identity).filled(:string)
      end

      rule(:invocation, :source, :expected_identity) do
        invocation = values[:invocation]
        command = invocation.command
        source = values[:source]
        payload = source.payload
        failures = []
        failures << "source must be the exact superseding partition" unless source.reference == command.superseding_partition_event
        failures << "source event must match the invocation" unless source.event == invocation.source_event
        failures << "source global position must match" unless command.source_global_position == source.event.global_position
        failures << "source must be a DecisionPartitionAdvanced event" unless payload.is_a?(Events::DecisionPartitionAdvancedV1)
        failures << "source must be the Candidate partition for the ChangeSet" unless candidate_partition?(payload, command.change_set_id)
        failures << "scan and command IDs must match the canonical identity" unless command.scan_id == values[:expected_identity] && command.command_id == values[:expected_identity]
        failures << "actor must be the validity policy" unless command.actor.kind == "system" && command.actor.id == "verification-obligation-validity-policy"
        failures.each { key(:invocation).failure(_1) }
      end

      private

      def candidate_partition?(payload, change_set_id)
        return false unless payload.is_a?(Events::DecisionPartitionAdvancedV1)

        partition = payload.partition
        partition.topic_root == "candidate" &&
          partition.anchor_kind == "changeset" &&
          partition.anchor_id == change_set_id &&
          partition.partition_id == "changeset:#{change_set_id}:candidate"
      end
    end
  end
end
