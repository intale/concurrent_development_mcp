# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareDeclareWorkItemDependency < Dry::Operation
      def initialize(contract: Contracts::DeclareWorkItemDependency.new)
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
            message: "DeclareWorkItemDependency input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor_attributes = attributes.fetch(:actor)
        output_attributes = attributes.fetch(:required_output)

        Success(
          Commands::DeclareWorkItemDependency.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(
              kind: actor_attributes.fetch(:kind),
              id: actor_attributes.fetch(:id)
            ),
            change_set_id: attributes.fetch(:change_set_id),
            dependency_id: attributes.fetch(:dependency_id),
            producer_work_item_id: attributes.fetch(:producer_work_item_id),
            consumer_work_item_id: attributes.fetch(:consumer_work_item_id),
            dependency_kind: attributes.fetch(:dependency_kind),
            required_output: output_attributes && RequiredOutput.new(output_attributes)
          )
        )
      end
    end
  end
end
