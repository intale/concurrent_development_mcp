# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DevelopmentArtifactRelationList < Dry::Operation
      def initialize(
        contract: Contracts::DevelopmentArtifactRelationList.new,
        artifacts: Repositories::DevelopmentArtifacts.new
      )
        @contract = contract
        @artifacts = artifacts
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = build_query(validated)
        page = @artifacts.relation_page(query)
        warnings = []
        unless page.artifact
          warnings << "The anchor Artifact is not yet observed; available relation rows are still served."
        end
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available directed Development Artifact relationships.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DevelopmentArtifactRelationPageData.new(page:),
          warnings:,
          next_actions: []
        )
      end

      private

      def build_query(validated)
        cursor = validated[:cursor] || {
          after_observed_sequence: 0,
          through_observed_sequence: nil,
          after_declared_global_position: nil,
          after_relation_id: nil
        }
        DevelopmentArtifactRelationQueryV1.new(
          artifact_id: validated[:artifact_id],
          direction: validated[:direction] || "both",
          relation: validated[:relation],
          include_superseded: validated[:include_superseded] || false,
          cursor: DevelopmentArtifactRelationPageV1::Cursor.new(cursor),
          limit: validated[:limit] || 20
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "development_artifact_relation_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "development_artifact_relation_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
