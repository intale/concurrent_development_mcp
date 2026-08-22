# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class CoordContext < Dry::Operation
      def initialize(
        contract: Contracts::CoordContext.new,
        contexts: Repositories::CoordContexts.new,
        scope_builder: ContextScopeBuilder.new,
        blockers_builder: ContextBlockersBuilder.new,
        next_actions_builder: ContextNextActionsBuilder.new,
        canonical_json: CanonicalJson.new
      )
        @contract = contract
        @contexts = contexts
        @scope_builder = scope_builder
        @blockers_builder = blockers_builder
        @next_actions_builder = next_actions_builder
        @canonical_json = canonical_json
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = build_query(validated.to_h)
        snapshot = @contexts.resolve(scope_kind: query.scope_kind, scope_id: query.scope_id)
        return context_not_found(query) unless snapshot

        scope = @scope_builder.call(query, snapshot.state)
        return context_not_found(query) unless scope

        current_result(query, scope, snapshot)
      end

      private

      def build_query(attributes)
        root_name = Contracts::CoordContext::ROOT_KEYS.find { attributes[_1].is_a?(String) }
        CoordContextQueryV1.new(
          scope_kind: root_name.to_s.delete_suffix("_id"),
          scope_id: attributes.fetch(root_name),
          context_token: attributes[:context_token]
        )
      end

      def current_result(query, scope, snapshot)
        token = context_token(scope, snapshot.source_positions)
        data = if query.context_token == token
          QueryResultV1::NotModifiedData.new(
            scope:,
            last_processed_at: snapshot.last_processed_at
          )
        else
          QueryResultV1::ContextData.new(
            scope:,
            context: snapshot.state,
            blockers: @blockers_builder.call(scope, snapshot.state),
            last_processed_at: snapshot.last_processed_at
          )
        end

        QueryResultV1.new(
          status: query.context_token == token ? "not_modified" : "ok",
          summary: query.context_token == token ? "The projected coordination context has not changed." : "Latest available coordination context loaded.",
          command_id: nil,
          receipt: nil,
          context_token: token,
          data:,
          warnings: [],
          next_actions: query.context_token == token ? [] : @next_actions_builder.call(snapshot.state)
        )
      end

      def context_not_found(query)
        not_found_result("No projected coordination context exists for #{query.scope_kind} #{query.scope_id}.")
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "coord_context input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "coord_context input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end

      def not_found_result(summary)
        QueryResultV1.new(
          status: "not_found",
          summary:,
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::EmptyData.new({}),
          warnings: [],
          next_actions: []
        )
      end

      def context_token(scope, source_positions)
        @canonical_json.sha256(
          ContextTokenDocument.new(
            schema: "context-token/v2",
            scope:,
            source_positions:
          ).to_h
        )
      end
    end
  end
end
