# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationValidityScanStart < Dry::Validation::Contract
      include ProcessStepCausation

      params do
        required(:invocation).value(Types.Instance(VerificationObligationValidityScanInvocation))
        required(:source).value(Types.Instance(CandidateObligations::PersistedEventV1))
      end

      rule(:invocation, :source) do
        invocation = values[:invocation]
        command = invocation.command
        source = values[:source]
        payload = source.payload
        failures = []
        failures << "source must be the exact superseding partition" unless source.reference == command.superseding_partition_event
        failures << "source event must match the invocation" unless source.event == invocation.source_event
        failures << "source global position must match" unless command.source_global_position == source.event.global_position
        unless payload.is_a?(Events::DecisionPartitionAdvancedV1) ||
               payload.is_a?(Events::DecisionAddedToPartitionV1) ||
               payload.is_a?(Events::DecisionRemovedFromPartitionV1)
          failures << "source must be a Decision partition membership event"
        end
        failures << "source must be the Candidate partition for the ChangeSet" unless candidate_partition?(payload, command.change_set_id)
        failures << "scan ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.scan_id)
        failures << "command ID must be UUIDv7" unless Types::UUID_V7_PATTERN.match?(command.command_id)
        unless process_step_matches?(invocation.caused_by, command_id: command.command_id, target_entity_id: command.scan_id)
          failures << "causal parent must be the ProcessStep that allocated the scan command and identity"
        end
        failures << "actor must be the validity policy" unless command.actor.kind == "system" && command.actor.id == "verification-obligation-validity-policy"
        failures.each { key(:invocation).failure(_1) }
      end

      private

      def candidate_partition?(payload, change_set_id)
        if payload.is_a?(Events::DecisionPartitionAdvancedV1)
          partition = payload.partition
          partition.topic_root == "candidate" &&
            partition.anchor_kind == "changeset" &&
            partition.anchor_id == change_set_id &&
            partition.partition_id == "changeset:#{change_set_id}:candidate"
        else
          payload.partition_id == "changeset:#{change_set_id}:candidate"
        end
      end
    end
  end
end
