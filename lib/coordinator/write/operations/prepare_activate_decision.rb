# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareActivateDecision < Dry::Operation
      def initialize(contract: Contracts::ActivateDecision.new)
        @contract = contract
      end

      def call(input)
        attributes = step validate(input)

        step build_command(attributes)
      end

      private

      def build_command(attributes)
        actor = attributes.fetch(:actor)

        Success(
          Commands::ActivateDecision.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            decision_id: attributes.fetch(:decision_id),
            interpretation_id: attributes.fetch(:interpretation_id),
            rationale: Decisions::DecisionActivationRationaleV1.new(attributes.fetch(:rationale))
          )
        )
      end

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "ActivateDecision input is invalid",
            details: result.errors.to_h
          )
        )
      end
    end
  end
end
