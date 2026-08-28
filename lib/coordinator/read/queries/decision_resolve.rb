# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DecisionResolve < Dry::Operation
      MAXIMUM_PARTITIONS = 8
      MAXIMUM_ACTIVE_DECISIONS = 32

      def initialize(
        contract: Contracts::DecisionResolve.new,
        governance: Repositories::DecisionGovernance.new,
        partition_selector: DecisionResolution::PartitionSelector.new,
        resolver: DecisionResolution::Resolver.new,
        topic_registry: Coordinator::Write::Interpretations::TopicRegistry.new,
        canonical_json: CanonicalJson.new,
        clock: Coordinator::Shared::SystemClock.new
      )
        @contract = contract
        @governance = governance
        @partition_selector = partition_selector
        @resolver = resolver
        @topic_registry = topic_registry
        @canonical_json = canonical_json
        @clock = clock
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = build_query(validated.to_h)
        topic = @topic_registry.fetch(query.topic_id)
        return unsupported_topic_result(query.topic_id) unless topic
        return unsupported_strategy_result(topic) unless topic.resolution_strategy == "single_choice"

        partitions = @partition_selector.call(query.context, topic_id: query.topic_id)
        return partition_limit_result(partitions.length) if partitions.length > MAXIMUM_PARTITIONS

        observations = @governance.partition_observations(partitions)
        heads = exact_heads(observations)
        return decision_limit_result(partitions.length, heads.length) if heads.length > MAXIMUM_ACTIVE_DECISIONS

        resolved_at = @clock.now
        resolution = @resolver.call(
          topic_id: query.topic_id,
          context: query.context,
          observations:,
          decisions: @governance.fetch_many(heads.map(&:decision_id).uniq),
          resolved_at:
        )
        return unsupported_result(resolution) unless resolution.unsupported_dimensions.empty?

        context = decision_context(query, observations, resolution, resolved_at)
        context_result(context, resolution)
      end

      private

      def build_query(attributes)
        context = attributes.fetch(:context)
        DecisionResolveQueryV1.new(
          topic_id: attributes.fetch(:topic_id),
          context: DecisionResolution::QueryContextV1.new(
            workspace_id: context[:workspace_id],
            repository_id: context.fetch(:repository_id),
            change_set_id: context.fetch(:change_set_id),
            work_item_id: context.fetch(:work_item_id),
            attempt_id: context.fetch(:attempt_id),
            phase: context.fetch(:phase),
            language: context.fetch(:language),
            paths: context.fetch(:paths).uniq.sort_by(&:b),
            environment: context[:environment],
            agent_role: context.fetch(:agent_role)
          )
        )
      end

      def exact_heads(observations)
        observations.flat_map(&:active_decisions)
          .uniq { [ _1.decision_id, _1.event.event_id ] }
          .sort_by { [ _1.decision_id.b, _1.event.event_id.b ] }
      end

      def decision_context(query, observations, resolution, resolved_at)
        document = DecisionResolution::ContextDocumentV1.new(
          schema: "decision-context/v1",
          resolution_policy: resolution_policy(query.topic_id),
          topic_id: query.topic_id,
          query_context: query.context,
          partitions: observations,
          effective_decision: resolution.effective_decision,
          shadowed_decisions: resolution.shadowed_decisions,
          conflict: resolution.conflict
        )
        DecisionResolution::ContextV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h),
          resolved_at:
        )
      end

      def context_result(context, resolution)
        conflict = !resolution.conflict.nil?
        QueryResultV1.new(
          status: conflict ? "conflict" : "ok",
          summary: conflict ? "Latest available Decision context has a specificity conflict." : "Latest available Decision context resolved.",
          command_id: nil,
          receipt: nil,
          context_token: context.digest,
          data: QueryResultV1::DecisionContextData.new(decision_context: context),
          warnings: unresolved_warnings(resolution.unresolved_decisions),
          next_actions: []
        )
      end

      def resolution_policy(topic_id)
        topic_id == "testing.framework" ? "testing-framework-resolution/v1" : "single-choice-resolution/v1"
      end

      def unsupported_topic_result(topic_id)
        unsupported_result_for(
          code: "decision_topic_not_supported",
          message: "Decision topic is not present in the executable registry",
          details: { topic_id: }
        )
      end

      def unsupported_strategy_result(topic)
        unsupported_result_for(
          code: "decision_resolution_strategy_not_supported",
          message: "decision_resolve supports only single-choice topics in this protocol version",
          details: { topic_id: topic.topic_id, resolution_strategy: topic.resolution_strategy }
        )
      end

      def unsupported_result_for(code:, message:, details:)
        QueryResultV1.new(
          status: "invalid",
          summary: message,
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(code:, message:, details:),
          warnings: [],
          next_actions: []
        )
      end

      def unresolved_warnings(heads)
        heads.map do |head|
          "decision_definition_not_observed:#{head.decision_id}:#{head.event.event_id}"
        end
      end

      def unsupported_result(resolution)
        QueryResultV1.new(
          status: "invalid",
          summary: "Available Decisions require context dimensions unsupported by decision_resolve version 1.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "unsupported_context_dimension",
            message: "One or more active Decisions cannot be evaluated by this resolver version",
            details: {
              dimensions: resolution.unsupported_dimensions,
              decision_heads: resolution.unsupported_decisions.map(&:to_h)
            }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def partition_limit_result(partition_count)
        limit_result(
          message: "Decision context exceeds the partition bound",
          details: { partition_count:, maximum_partition_count: MAXIMUM_PARTITIONS }
        )
      end

      def decision_limit_result(partition_count, active_decision_count)
        limit_result(
          message: "Decision context exceeds the active Decision-head bound",
          details: {
            partition_count:,
            active_decision_count:,
            maximum_active_decision_count: MAXIMUM_ACTIVE_DECISIONS
          }
        )
      end

      def limit_result(message:, details:)
        QueryResultV1.new(
          status: "limit_reached",
          summary: message,
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "decision_context_limit_reached",
            message:,
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "decision_resolve input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "decision_resolve input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
