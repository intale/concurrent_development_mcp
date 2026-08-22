# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCreateWorkItem < Dry::Operation
      def initialize(contract: Contracts::CreateWorkItem.new)
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
            message: "CreateWorkItem input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor_attributes = attributes.fetch(:actor)

        Success(
          Commands::CreateWorkItem.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(
              kind: actor_attributes.fetch(:kind),
              id: actor_attributes.fetch(:id)
            ),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            repository_id: attributes.fetch(:repository_id),
            goal: attributes.fetch(:goal),
            acceptance_criteria: attributes.fetch(:acceptance_criteria)
          )
        )
      end
    end
  end
end
