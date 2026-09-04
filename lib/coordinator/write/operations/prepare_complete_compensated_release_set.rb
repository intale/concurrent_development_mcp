# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCompleteCompensatedReleaseSet < Dry::Operation
      RULE_VERSION = "release-set-completion/v1"

      def initialize(contract: Contracts::CompleteCompensatedReleaseSet.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Commands::CompleteCompensatedReleaseSet.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          release_set_id: attributes.fetch(:release_set_id),
          compensation_request_event: EventReference.new(attributes.fetch(:compensation_request_event)),
          evidence: attributes.fetch(:evidence).map { build_evidence(_1) },
          rule_version: RULE_VERSION
        )
      end

      private

      def build_evidence(item)
        ReleaseSets::CompensationEvidenceV2.new(
          **item,
          integration_event: EventReference.new(item.fetch(:integration_event)),
          producer: ReleaseSets::EvidenceProducerV1.new(item.fetch(:producer))
        )
      end

      def invalid(details)
        Failure(OutcomeError.new(code: :invalid_input, message: "CompleteCompensatedReleaseSet input is invalid", details:))
      end
    end
  end
end
