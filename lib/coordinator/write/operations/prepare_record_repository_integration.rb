# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRecordRepositoryIntegration < Dry::Operation
      POLICY_VERSION = "release-set-integration/v1"

      def initialize(contract: Contracts::RecordRepositoryIntegration.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Commands::RecordRepositoryIntegration.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          release_set_id: attributes.fetch(:release_set_id),
          repository_id: attributes.fetch(:repository_id),
          attempt_id: attributes.fetch(:attempt_id),
          outcome: attributes.fetch(:outcome),
          merge_observation_event: event_reference(attributes.fetch(:merge_observation_event)),
          observation_digest: attributes.fetch(:observation_digest),
          failure: integration_failure(attributes.fetch(:failure)),
          policy_version: POLICY_VERSION
        )
      end

      private

      def event_reference(attributes)
        EventReference.new(attributes) if attributes
      end

      def integration_failure(attributes)
        return unless attributes

        ReleaseSets::IntegrationFailureV2.new(
          **attributes,
          producer: ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer))
        )
      end

      def invalid(details)
        Failure(OutcomeError.new(code: :invalid_input, message: "RecordRepositoryIntegration input is invalid", details:))
      end
    end
  end
end
