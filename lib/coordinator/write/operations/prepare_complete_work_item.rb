# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCompleteWorkItem < Dry::Operation
      def initialize(contract: Contracts::CompleteWorkItem.new)
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

        invalid(result.errors.to_h)
      end

      def build_command(attributes)
        actor = attributes.fetch(:actor)
        outputs = attributes.fetch(:produced_outputs).map do |output|
          WorkItemOutputV1.new(output)
        end.sort_by { [ _1.kind.b, _1.key.b ] }

        Success(
          Commands::CompleteWorkItem.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            attempt_id: attributes.fetch(:attempt_id),
            candidate_id: attributes.fetch(:candidate_id),
            produced_outputs: outputs
          )
        )
      end

      def invalid(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "CompleteWorkItem input is invalid",
            details:
          )
        )
      end
    end
  end
end
