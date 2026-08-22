# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationSlotBuilder
      def initialize(
        topic_registry: TopicRegistry.new,
        canonical_json: CanonicalJson.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @topic_registry = topic_registry
        @canonical_json = canonical_json
        @compound_marker_builder = compound_marker_builder
      end

      def call(proposal)
        decision = proposal.proposed_decision
        definition = @topic_registry.fetch(decision.topic_id)
        raise KeyError, "missing topic definition for #{decision.topic_id}" unless definition

        scope = normalize_scope(decision.scope)
        document = InterpretationSlotDocumentV1.new(
          schema: "interpretation-adjudication-slot/v1",
          source_message_id: proposal.source_message_id,
          topic_id: decision.topic_id,
          exact_scope: scope,
          conflict_dimension: definition.conflict_dimension,
          resolution_strategy: definition.resolution_strategy
        )
        scope_digest = @canonical_json.sha256(scope.to_h)
        compound_marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "interpretation-slot",
            components: [
              "message:#{proposal.source_message_id}",
              "topic:#{decision.topic_id}",
              "scope:v1:#{scope_digest}",
              "conflict-dimension:#{definition.conflict_dimension}",
              "resolution-strategy:#{definition.resolution_strategy}"
            ]
          )
        )

        InterpretationSlotV1.new(document:, scope_digest:, compound_marker:)
      end

      private

      def normalize_scope(scope)
        DecisionScopeV1.new(
          workspace_id: scope.workspace_id,
          repository_ids: normalize(scope.repository_ids),
          branch_selectors: normalize(scope.branch_selectors),
          change_set_id: scope.change_set_id,
          work_item_id: scope.work_item_id,
          attempt_id: scope.attempt_id,
          candidate_id: scope.candidate_id,
          path_selectors: normalize(scope.path_selectors),
          symbol_selectors: normalize(scope.symbol_selectors),
          contract_selectors: normalize(scope.contract_selectors),
          schema_selectors: normalize(scope.schema_selectors),
          environments: normalize(scope.environments),
          agent_roles: normalize(scope.agent_roles)
        )
      end

      def normalize(values)
        values.uniq.sort_by(&:b)
      end
    end
  end
end
