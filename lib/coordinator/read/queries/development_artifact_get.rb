# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DevelopmentArtifactGet < Dry::Operation
      def initialize(
        contract: Contracts::DevelopmentArtifactGet.new,
        artifacts: Repositories::DevelopmentArtifacts.new
      )
        @contract = contract
        @artifacts = artifacts
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = DevelopmentArtifactGetQueryV1.new(
          artifact_id: validated[:artifact_id],
          observation_id: validated[:observation_id]
        )
        artifact = @artifacts.fetch(query.artifact_id, observation_id: query.observation_id)
        return not_found_result(query) unless artifact

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Development Artifact metadata and relationships.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DevelopmentArtifactData.new(artifact:),
          warnings: [],
          next_actions: []
        )
      end

      private

      def not_found_result(query)
        result(
          status: "not_found",
          summary: "No projected Development Artifact is currently available for this ID.",
          code: "development_artifact_not_observed",
          message: "The read side has not observed this Development Artifact",
          details: {
            artifact_id: query.artifact_id,
            observation_id: query.observation_id
          }
        )
      end

      def invalid_result(details)
        result(
          status: "invalid",
          summary: "development_artifact_get input is invalid.",
          code: "invalid_input",
          message: "development_artifact_get input is invalid",
          details:
        )
      end

      def result(status:, summary:, code:, message:, details:)
        QueryResultV1.new(
          status:,
          summary:,
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(code:, message:, details:),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
