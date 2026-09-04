# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRecordReleaseSetActivation < Dry::Operation
      POLICY_VERSION = "release-set-activation/v1"

      def initialize(contract: Contracts::RecordReleaseSetActivation.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        point = attributes.fetch(:activation_point)
        Commands::RecordReleaseSetActivation.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          release_set_id: attributes.fetch(:release_set_id),
          verification_event: EventReference.new(attributes.fetch(:verification_event)),
          verification_digest: attributes.fetch(:verification_digest),
          activation_point: ReleaseSets::ActivationPointV2.new(
            **point,
            producer: ReleaseSets::EvidenceProducerV1.new(point.fetch(:producer))
          ),
          policy_version: POLICY_VERSION
        )
      end

      private

      def invalid(details)
        Failure(OutcomeError.new(code: :invalid_input, message: "RecordReleaseSetActivation input is invalid", details:))
      end
    end
  end
end
