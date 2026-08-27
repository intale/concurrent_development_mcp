# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareAndSubmitCoordinationTask
      include Dry::Monads[:result]

      def initialize(
        preparer:,
        submitter:,
        public_command_contract: Contracts::PublicCommand.new
      )
        @preparer = preparer
        @submitter = submitter
        @public_command_contract = public_command_contract
      end

      def call(input)
        @preparer.call(input)
          .bind { validate_public_command(_1) }
          .bind { @submitter.call(_1) }
      end

      private

      def validate_public_command(command)
        result = @public_command_contract.call(command_id: command.command_id)
        return Success(command) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "Public command ID is invalid",
            details: result.errors.to_h
          )
        )
      end
    end
  end
end
