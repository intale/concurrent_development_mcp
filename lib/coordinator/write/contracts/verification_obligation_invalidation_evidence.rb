# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationInvalidationEvidence < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::InvalidateVerificationObligation))
        required(:obligation).value(Types.Instance(CandidateObligations::PersistedEventV1))
        required(:superseding_partition).value(Types.Instance(CandidateObligations::PersistedEventV1))
      end

      rule(:command, :obligation, :superseding_partition) do
        command = values[:command]
        obligation = values[:obligation]
        superseding = values[:superseding_partition]
        creation = obligation.payload
        partition = superseding.payload
        failures = []
        failures << "obligation reference must resolve exactly" unless obligation.reference == command.obligation_event
        failures << "obligation payload must match the command" unless creation.is_a?(Events::VerificationObligationCreatedV1) && creation.obligation_id == command.obligation_id
        failures << "superseding partition reference must resolve exactly" unless superseding.reference == command.superseding_partition_event
        failures << "superseding event must be a DecisionPartitionAdvanced fact" unless partition.is_a?(Events::DecisionPartitionAdvancedV1)
        failures << "superseding event must be the matching Candidate partition" unless matching_candidate_partition?(creation, partition)
        failures.each { key(:command).failure(_1) }
      end

      private

      def matching_candidate_partition?(creation, partition_event)
        return false unless creation.is_a?(Events::VerificationObligationCreatedV1)
        return false unless partition_event.is_a?(Events::DecisionPartitionAdvancedV1)

        prior = creation.policy.partition_event
        current = partition_event.partition
        current.topic_root == "candidate" &&
          current.anchor_kind == "changeset" &&
          current.anchor_id == creation.change_set_id &&
          current.partition_id == prior.stream_id &&
          prior.stream_context == "HumanGuidance" &&
          prior.stream_name == "DecisionPartition"
      end
    end
  end
end
