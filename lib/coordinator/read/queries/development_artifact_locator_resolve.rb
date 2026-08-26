# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DevelopmentArtifactLocatorResolve < Dry::Operation
      def initialize(
        contract: Contracts::DevelopmentArtifactLocatorResolve.new,
        artifacts: Repositories::DevelopmentArtifacts.new
      )
        @contract = contract
        @artifacts = artifacts
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = build_query(validated)
        page = @artifacts.locator_page(query)
        QueryResultV1.new(
          status: "ok",
          summary: summary(page.resolution),
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DevelopmentArtifactLocatorPageData.new(page:),
          warnings: warnings(page.resolution),
          next_actions: next_actions(query, page)
        )
      end

      private

      def build_query(validated)
        cursor = validated[:cursor] || {
          after_observed_sequence: 0,
          through_observed_sequence: nil,
          after_captured_global_position: nil,
          after_artifact_id: nil
        }
        DevelopmentArtifactLocatorQueryV1.new(
          scope: validated[:scope],
          source_kind: validated[:source_kind],
          locator: validated[:locator],
          source_revision: validated[:source_revision],
          revision_specified: validated.key?(:source_revision),
          cursor: DevelopmentArtifactLocatorPageV1::Cursor.new(cursor),
          limit: validated[:limit] || 20
        )
      end

      def summary(resolution)
        case resolution
        when "absent" then "No currently projected Artifact matches the exact logical locator."
        when "unique" then "One currently projected Artifact matches the exact logical locator."
        else "Multiple projected Artifacts match; no version was selected implicitly."
        end
      end

      def warnings(resolution)
        case resolution
        when "absent"
          [ "Projection lag remains possible; reuse the returned continuation cursor to retry." ]
        when "ambiguous"
          [ "Specify an exact source_revision or inspect the returned immutable revisions." ]
        else []
        end
      end

      def next_actions(query, page)
        actions = []
        if page.resolution == "unique" && page.items.one?
          actions << Coordinator::Write::NextAction.new(
            tool: "development_artifact_content_get",
            arguments: Coordinator::Write::NextAction::DevelopmentArtifactArguments.new(
              artifact_id: page.items.sole.artifact_id
            )
          )
        end
        if page.resolution == "ambiguous"
          page.items.map { _1.source.revision }.uniq.first(10).each do |revision|
            actions << locator_action(
              query,
              page.continuation_cursor,
              source_revision: revision,
              revision_specified: true
            )
          end
        end
        if page.resolution == "absent" || page.has_more
          actions << locator_action(
            query,
            page.continuation_cursor,
            source_revision: query.source_revision,
            revision_specified: query.revision_specified
          )
        end
        actions
      end

      def locator_action(query, cursor, source_revision:, revision_specified:)
        attributes = {
          scope: query.scope,
          source_kind: query.source_kind,
          locator: query.locator,
          cursor:,
          limit: query.limit
        }
        attributes[:source_revision] = source_revision if revision_specified
        NextAction.new(
          tool: "development_artifact_locator_resolve",
          arguments: NextAction::DevelopmentArtifactLocatorArguments.new(attributes)
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "development_artifact_locator_resolve input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "development_artifact_locator_resolve input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
