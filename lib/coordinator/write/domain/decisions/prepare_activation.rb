# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Decisions
      class PrepareActivation
        include Dry::Monads[:result]

        def initialize(
          eligibility: ActivationEligibility.new,
          definition_builder: Coordinator::Write::Decisions::DecisionDefinitionBuilder.new,
          slot_builder: Coordinator::Write::Decisions::DecisionSlotBuilder.new,
          partition_builder: Coordinator::Write::Decisions::DecisionPartitionBuilder.new
        )
          @eligibility = eligibility
          @definition_builder = definition_builder
          @slot_builder = slot_builder
          @partition_builder = partition_builder
        end

        def call(command:, proposal:, acceptance:, activated_at:, recorded_event:, activated_event:)
          return not_accepted(command) unless accepted_evidence?(command, proposal, acceptance)

          eligibility = @eligibility.call(proposal: proposal.proposal, activated_at:)
          return eligibility if eligibility.failure?

          definition = @definition_builder.call(
            proposal: proposal.proposal,
            valid_from_default: activated_at
          )
          partitions = @partition_builder.call(definition)
          return partition_limit(command, partitions.length) if partitions.length > 32

          Success(
            Coordinator::Write::Decisions::DecisionActivationCandidateV1.new(
              proposal:,
              acceptance:,
              definition:,
              slot: @slot_builder.call(definition),
              partitions:,
              recorded_event:,
              activated_event:
            )
          )
        end

        private

        def accepted_evidence?(command, proposal, acceptance)
          return false unless proposal && acceptance

          accepted = acceptance.acceptance
          proposed = proposal.proposal
          identities_match = accepted.interpretation_id == command.interpretation_id &&
            proposed.interpretation_id == command.interpretation_id &&
            accepted.source_message_id == proposed.source_message_id
          return false unless identities_match

          !accepted.respond_to?(:proposal_event) || accepted.proposal_event == proposal.event
        end

        def not_accepted(command)
          Failure(
            OutcomeError.new(
              code: :interpretation_not_accepted,
              message: "Decision activation requires an accepted interpretation",
              details: { interpretation_id: command.interpretation_id }
            )
          )
        end

        def partition_limit(command, count)
          Failure(
            OutcomeError.new(
              code: :decision_partition_limit_reached,
              message: "Decision activation affects more than 32 partitions",
              details: {
                decision_id: command.decision_id,
                partition_count: count,
                maximum_partition_count: 32
              }
            )
          )
        end
      end
    end
  end
end
