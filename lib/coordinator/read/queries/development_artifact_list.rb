# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DevelopmentArtifactList < Dry::Operation
      def initialize(
        contract: Contracts::DevelopmentArtifactList.new,
        artifacts: Repositories::DevelopmentArtifacts.new
      )
        @contract = contract
        @artifacts = artifacts
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        target = validated[:relation_target]
        query = DevelopmentArtifactListQueryV1.new(
          scope: validated[:scope],
          kind: validated[:kind],
          labels: validated[:labels] || [],
          source_kind: validated[:source_kind],
          relation_target_kind: target && target[:kind],
          relation_target_id: target && target[:id],
          after_global_position: validated[:after_global_position],
          limit: validated[:limit] || 20
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Available projected Development Artifacts in capture order.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DevelopmentArtifactPageData.new(page: @artifacts.page(query)),
          warnings: [],
          next_actions: []
        )
      end

      private

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "development_artifact_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "development_artifact_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
