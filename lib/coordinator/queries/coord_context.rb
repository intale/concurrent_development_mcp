# frozen_string_literal: true

module Coordinator
  module Queries
    class CoordContext < Dry::Operation
      def initialize(
        contract: Contracts::CoordContext.new,
        contexts: Repositories::CoordContexts.new,
        completion_lookup: CommandCompletionLookup.new,
        progress: CoordContextProgress.new,
        scope_builder: ContextScopeBuilder.new,
        blockers_builder: ContextBlockersBuilder.new,
        next_actions_builder: ContextNextActionsBuilder.new,
        canonical_json: CanonicalJson.new
      )
        @contract = contract
        @contexts = contexts
        @completion_lookup = completion_lookup
        @progress = progress
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

        completion = query.after_command_id && @completion_lookup.fetch(query.after_command_id)
        return command_not_found(query, scope) if query.after_command_id && !completion
        return scope_mismatch(query, scope, completion) if completion && completion.data.change_set_id != scope.change_set_id

        progress = completion && @progress.call(completion)
        return pending_result(query, scope, completion, progress) if progress && !progress.complete

        current_result(query, scope, snapshot, completion:)
      end

      private

      def build_query(attributes)
        root_name = Contracts::CoordContext::ROOT_KEYS.find { attributes[_1].is_a?(String) }
        CoordContextQueryV1.new(
          scope_kind: root_name.to_s.delete_suffix("_id"),
          scope_id: attributes.fetch(root_name),
          after_command_id: attributes[:after_command_id],
          context_token: attributes[:context_token]
        )
      end

      def current_result(query, scope, snapshot, completion:)
        freshness = completion ? "current_for_requested_command" : "observed"
        token = context_token(scope, snapshot.source_positions)
        data = if query.context_token == token
          McpResultV1::NotModifiedData.new(
            scope:,
            freshness:,
            last_processed_at: snapshot.last_processed_at
          )
        else
          McpResultV1::ContextData.new(
            scope:,
            context: snapshot.state,
            blockers: @blockers_builder.call(scope, snapshot.state),
            source_positions: snapshot.source_positions,
            freshness:,
            last_processed_at: snapshot.last_processed_at
          )
        end

        McpResultV1.new(
          status: query.context_token == token ? "not_modified" : "ok",
          summary: query.context_token == token ? "The coordination context has not changed." : "Coordination context loaded.",
          command_id: completion&.command_id,
          receipt: completion&.receipt,
          context_token: token,
          data:,
          warnings: [],
          next_actions: query.context_token == token ? [] : @next_actions_builder.call(snapshot.state),
          projection_status: freshness
        )
      end

      def pending_result(query, scope, completion, progress)
        McpResultV1.new(
          status: "pending_projection",
          summary: "The command committed, but the requested coordination context is not current yet.",
          command_id: completion.command_id,
          receipt: completion.receipt,
          context_token: completion.context_token,
          data: McpResultV1::PendingContextData.new(scope:, projection_progress: [ progress ]),
          warnings: [],
          next_actions: [ context_refresh(query) ],
          projection_status: "pending"
        )
      end

      def context_not_found(query)
        not_found_result("No projected coordination context exists for #{query.scope_kind} #{query.scope_id}.")
      end

      def command_not_found(query, scope)
        McpResultV1.new(
          status: "not_found",
          summary: "No completed after-command exists for the supplied command ID.",
          command_id: query.after_command_id,
          receipt: nil,
          context_token: nil,
          data: McpResultV1::DomainError.new(
            code: "after_command_not_found",
            message: "after_command_id does not identify a completed command",
            details: { command_id: query.after_command_id, scope: scope.to_h }
          ),
          warnings: [],
          next_actions: [],
          projection_status: nil
        )
      end

      def scope_mismatch(query, scope, completion)
        McpResultV1.new(
          status: "invalid",
          summary: "The after-command belongs to another ChangeSet.",
          command_id: query.after_command_id,
          receipt: completion.receipt,
          context_token: nil,
          data: McpResultV1::DomainError.new(
            code: "context_scope_mismatch",
            message: "after_command_id does not belong to the requested context scope",
            details: { requested_change_set_id: scope.change_set_id, command_change_set_id: completion.data.change_set_id }
          ),
          warnings: [],
          next_actions: [],
          projection_status: nil
        )
      end

      def invalid_result(details)
        McpResultV1.new(
          status: "invalid",
          summary: "coord_context input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: McpResultV1::DomainError.new(
            code: "invalid_input",
            message: "coord_context input is invalid",
            details:
          ),
          warnings: [],
          next_actions: [],
          projection_status: nil
        )
      end

      def not_found_result(summary)
        McpResultV1.new(
          status: "not_found",
          summary:,
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: McpResultV1::EmptyData.new({}),
          warnings: [],
          next_actions: [],
          projection_status: nil
        )
      end

      def context_token(scope, source_positions)
        @canonical_json.sha256(
          ContextTokenDocument.new(
            schema: "context-token/v1",
            scope:,
            projection_barriers: ProjectionBarriers.new(coord_context_v1: source_positions)
          ).to_h
        )
      end

      def context_refresh(query)
        arguments = case query.scope_kind
        when "change_set"
          NextAction::ContextArguments.new(
            change_set_id: query.scope_id,
            after_command_id: query.after_command_id
          )
        when "work_item"
          NextAction::WorkItemContextArguments.new(
            work_item_id: query.scope_id,
            after_command_id: query.after_command_id
          )
        when "attempt"
          NextAction::AttemptContextArguments.new(
            attempt_id: query.scope_id,
            after_command_id: query.after_command_id
          )
        end
        NextAction.new(tool: "coord_context", arguments:)
      end
    end
  end
end
