# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareClaimVerificationObligation < Dry::Operation
      def initialize(contract: Contracts::ClaimVerificationObligation.new)
        @contract = contract
      end

      def call(input)
        attributes = step validate(input)

        step build_command(attributes)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "ClaimVerificationObligation input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor = attributes.fetch(:actor)
        Success(
          Commands::ClaimVerificationObligation.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            obligation_id: attributes.fetch(:obligation_id),
            claim_duration_seconds: attributes.fetch(:claim_duration_seconds)
          )
        )
      end
    end
  end
end
