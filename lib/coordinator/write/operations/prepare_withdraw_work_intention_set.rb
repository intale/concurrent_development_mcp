# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareWithdrawWorkIntentionSet < Dry::Operation
      def initialize(contract: Contracts::WithdrawWorkIntentionSet.new)
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
            message: "WithdrawWorkIntentionSet input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor = attributes.fetch(:actor)
        intentions = attributes.fetch(:intentions).map do |reference|
          WorkIntentionFencedReferenceV1.new(
            resource_id: reference.fetch(:resource_id),
            intention_id: reference.fetch(:intention_id),
            fencing_token: reference.fetch(:fencing_token)
          )
        end.sort_by { _1.resource_id.b }

        Success(
          Commands::WithdrawWorkIntentionSet.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            attempt_id: attributes.fetch(:attempt_id),
            intention_set_id: attributes.fetch(:intention_set_id),
            intentions:
          )
        )
      end
    end
  end
end
