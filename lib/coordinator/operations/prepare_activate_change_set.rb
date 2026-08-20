# frozen_string_literal: true

module Coordinator
  module Operations
    class PrepareActivateChangeSet < Dry::Operation
      def initialize(contract: Contracts::ActivateChangeSet.new)
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
            message: "ActivateChangeSet input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor_attributes = attributes.fetch(:actor)

        Success(
          Commands::ActivateChangeSet.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(
              kind: actor_attributes.fetch(:kind),
              id: actor_attributes.fetch(:id)
            ),
            change_set_id: attributes.fetch(:change_set_id)
          )
        )
      end
    end
  end
end
