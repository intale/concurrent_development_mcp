# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class GuidanceGet < Dry::Operation
      def initialize(
        contract: Contracts::GuidanceGet.new,
        utterances: Repositories::UserUtterances.new
      )
        @contract = contract
        @utterances = utterances
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = GuidanceGetQueryV1.new(message_id: validated[:message_id])
        guidance = @utterances.fetch(query.message_id)
        return not_found_result(query.message_id) unless guidance

        QueryResultV1.new(
          status: "ok",
          summary: "Available attributed guidance evidence.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::GuidanceData.new(guidance:),
          warnings: [],
          next_actions: []
        )
      end

      private

      def not_found_result(message_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected guidance evidence exists for the supplied message ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "guidance_not_observed",
            message: "The read side has not observed this guidance message",
            details: { message_id: }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "guidance_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "guidance_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
