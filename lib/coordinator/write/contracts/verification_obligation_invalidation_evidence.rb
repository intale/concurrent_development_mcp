# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationInvalidationEvidence < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::InvalidateVerificationObligation))
        required(:obligation).value(Types.Instance(VerificationObligations::LoadedDefinitionV2))
        required(:superseding_partition).value(Types.Instance(CandidateObligations::PersistedEventV1))
      end

      rule(:command, :obligation, :superseding_partition) do
        command = values[:command]
        loaded = values[:obligation]
        superseding = values[:superseding_partition]
        definition = loaded.definition
        partition = superseding.payload
        failures = []
        failures << "obligation reference must resolve exactly" unless loaded.reference == command.obligation_event
        failures << "obligation identity must match the command" unless definition.obligation_id == command.obligation_id
        failures << "superseding partition reference must resolve exactly" unless superseding.reference == command.superseding_partition_event
        unless partition.is_a?(Events::DecisionAddedToPartitionV1) ||
               partition.is_a?(Events::DecisionRemovedFromPartitionV1)
          failures << "superseding event must be a Decision partition membership fact"
        end
        failures << "superseding event must be the matching Candidate partition" unless matching_candidate_partition?(definition, partition)
        failures.each { key(:command).failure(_1) }
      end

      private

      def matching_candidate_partition?(definition, partition_event)
        prior = definition.policy.partition_event
        partition_id = partition_event.partition_id
        partition_id == "changeset:#{definition.change_set_id}:candidate" &&
          partition_id == prior.stream_id &&
          prior.stream_context == "HumanGuidance" &&
          prior.stream_name == "DecisionPartition"
      end
    end
  end
end
