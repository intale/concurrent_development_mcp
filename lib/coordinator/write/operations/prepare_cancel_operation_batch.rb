# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCancelOperationBatch < Dry::Operation
      def initialize(contract: Contracts::CancelOperationBatch.new)
        @contract = contract
      end

      def call(input)
        validated = @contract.call(input)
        return Failure(invalid(validated.errors.to_h)) if validated.failure?

        attributes = validated.to_h
        actor = attributes.fetch(:actor)
        Commands::CancelOperationBatch.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          batch_id: attributes.fetch(:batch_id)
        )
      end

      private

      def invalid(details)
        OutcomeError.new(
          code: :invalid_input,
          message: "operation_batch_cancel input is invalid",
          details:
        )
      end
    end
  end
end
