# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRecordReleaseSetVerification < Dry::Operation
      POLICY_VERSION = "release-set-verification/v1"

      def initialize(contract: Contracts::RecordReleaseSetVerification.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        evidence = attributes.fetch(:evidence)
        Commands::RecordReleaseSetVerification.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          release_set_id: attributes.fetch(:release_set_id),
          integration_events: attributes.fetch(:integration_events).map { EventReference.new(_1) },
          evidence: ReleaseSets::VerificationEvidenceV1.new(
            **evidence,
            producer: ReleaseSets::EvidenceProducerV1.new(evidence.fetch(:producer)),
            findings: evidence.fetch(:findings).map { ReleaseSets::VerificationFindingV1.new(_1) }
          ),
          policy_version: POLICY_VERSION
        )
      end

      private

      def invalid(details)
        Failure(OutcomeError.new(code: :invalid_input, message: "RecordReleaseSetVerification input is invalid", details:))
      end
    end
  end
end
