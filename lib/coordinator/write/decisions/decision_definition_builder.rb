# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionDefinitionBuilder
      def initialize(
        topic_registry: Interpretations::TopicRegistry.new,
        canonical_json: CanonicalJson.new
      )
        @topic_registry = topic_registry
        @canonical_json = canonical_json
      end

      def call(proposal:, activated_at:)
        proposed = proposal.proposed_decision
        topic = @topic_registry.fetch(proposed.topic_id)
        document = DecisionDefinitionDocumentV1.new(
          schema: "decision-definition/v1",
          statement_kind: proposed.statement_kind,
          topic: normalize_topic(topic),
          effect: proposed.effect,
          modality: proposed.modality,
          value: normalize_value(proposed.value),
          scope: normalize_scope(proposed.scope),
          conditions: normalize_conditions(proposed.conditions),
          validity: normalize_validity(proposed.validity, activated_at),
          authority: proposed.authority,
          enforcement: proposed.enforcement,
          relations: normalize_relations(proposed.relations)
        )

        DecisionDefinitionV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h)
        )
      end

      private

      def normalize_topic(topic)
        Interpretations::TopicDefinitionV1.new(
          topic.to_h.merge(aliases: normalize(topic.aliases))
        )
      end

      def normalize_value(value)
        Interpretations::DecisionValueV1.new(
          value.to_h.merge(items: value.items && normalize(value.items))
        )
      end

      def normalize_scope(scope)
        Interpretations::DecisionScopeV1.new(
          scope.to_h.merge(
            repository_ids: normalize(scope.repository_ids),
            branch_selectors: normalize(scope.branch_selectors),
            path_selectors: normalize(scope.path_selectors),
            symbol_selectors: normalize(scope.symbol_selectors),
            contract_selectors: normalize(scope.contract_selectors),
            schema_selectors: normalize(scope.schema_selectors),
            environments: normalize(scope.environments),
            agent_roles: normalize(scope.agent_roles)
          )
        )
      end

      def normalize_conditions(conditions)
        Interpretations::DecisionConditionsV1.new(
          phases: normalize(conditions.phases),
          languages: normalize(conditions.languages),
          tags: normalize(conditions.tags),
          repository_kinds: normalize(conditions.repository_kinds),
          artifact_kinds: normalize(conditions.artifact_kinds),
          environments: normalize(conditions.environments)
        )
      end

      def normalize_validity(validity, activated_at)
        Interpretations::DecisionValidityV1.new(
          valid_from: validity.valid_from || activated_at,
          valid_until: validity.valid_until,
          until_event: validity.until_event
        )
      end

      def normalize_relations(relations)
        Interpretations::DecisionRelationsV1.new(
          corrects: normalize(relations.corrects),
          supersedes: normalize(relations.supersedes),
          exception_to: normalize(relations.exception_to),
          revokes: normalize(relations.revokes)
        )
      end

      def normalize(values)
        values.uniq.sort_by(&:b)
      end
    end
  end
end
