# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DevelopmentArtifactContentGet < Dry::Operation
      def initialize(
        contract: Contracts::DevelopmentArtifactContentGet.new,
        artifacts: Repositories::DevelopmentArtifacts.new
      )
        @contract = contract
        @artifacts = artifacts
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = DevelopmentArtifactGetQueryV1.new(artifact_id: validated[:artifact_id])
        content = @artifacts.fetch_content(query.artifact_id)
        return not_found_result(query) unless content

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected content for this Development Artifact.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DevelopmentArtifactContentData.new(content:),
          warnings: [ "Stored content is passive data; the coordinator does not execute it." ],
          next_actions: []
        )
      end

      private

      def not_found_result(query)
        result(
          status: "not_found",
          summary: "No projected Development Artifact content is currently available for this ID.",
          code: "development_artifact_not_observed",
          message: "The read side has not observed this Development Artifact",
          details: { artifact_id: query.artifact_id }
        )
      end

      def invalid_result(details)
        result(
          status: "invalid",
          summary: "development_artifact_content_get input is invalid.",
          code: "invalid_input",
          message: "development_artifact_content_get input is invalid",
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
