# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class Resolver
      APPLICABILITY_REASONS = %w[
        topic_exact
        validity_current
        scope_matches
        conditions_match
      ].freeze
      ANCHOR_RANKS = {
        "workspace" => 1,
        "repository" => 2,
        "change_set" => 3,
        "work_item" => 4,
        "attempt" => 5
      }.freeze

      def call(topic_id:, context:, observations:, decisions:, resolved_at:)
        heads = exact_heads(observations)
        resolved = []
        unsupported_dimensions = []
        unsupported_decisions = []
        unresolved_decisions = []

        heads.each do |head|
          decision = exact_decision(head, decisions)
          unless decision
            unresolved_decisions << head
            next
          end

          definition = decision.definition
          document = definition.document
          next unless document.topic.topic_id == topic_id

          dimensions = unsupported_context_dimensions(document)
          unless dimensions.empty?
            unsupported_dimensions.concat(dimensions)
            unsupported_decisions << head
            next
          end
          next unless applicable?(document, context, resolved_at)

          resolved << resolved_decision(head, definition, document)
        end

        build_result(
          resolved:,
          unsupported_dimensions: unsupported_dimensions.uniq.sort_by(&:b),
          unsupported_decisions: sort_heads(unsupported_decisions),
          unresolved_decisions: sort_heads(unresolved_decisions)
        )
      end

      private

      def exact_heads(observations)
        sort_heads(
          observations
            .flat_map(&:active_decisions)
            .uniq { [ _1.decision_id, _1.event.event_id ] }
        )
      end

      def sort_heads(heads)
        heads.uniq { [ _1.decision_id, _1.event.event_id ] }
          .sort_by { [ _1.decision_id.b, _1.event.event_id.b ] }
          .freeze
      end

      def exact_decision(head, decisions)
        decisions.find do |decision|
          current = decision.current_head&.event
          decision.decision_id == head.decision_id &&
            current == head.event &&
            head.decision_revision == current.stream_revision
        end
      end

      def unsupported_context_dimensions(document)
        scope = document.scope
        conditions = document.conditions
        dimensions = []
        dimensions << "scope.branch_selectors" unless scope.branch_selectors.empty?
        dimensions << "scope.candidate_id" if scope.candidate_id
        dimensions << "scope.symbol_selectors" unless scope.symbol_selectors.empty?
        dimensions << "scope.contract_selectors" unless scope.contract_selectors.empty?
        dimensions << "scope.schema_selectors" unless scope.schema_selectors.empty?
        dimensions << "conditions.tags" unless conditions.tags.empty?
        dimensions << "conditions.repository_kinds" unless conditions.repository_kinds.empty?
        dimensions << "conditions.artifact_kinds" unless conditions.artifact_kinds.empty?
        dimensions << "validity.until_event" if document.validity.until_event
        dimensions
      end

      def applicable?(document, context, resolved_at)
        validity_current?(document.validity, resolved_at) &&
          scope_matches?(document.scope, context) &&
          conditions_match?(document.conditions, context)
      end

      def validity_current?(validity, resolved_at)
        (!validity.valid_from || validity.valid_from <= resolved_at) &&
          (!validity.valid_until || resolved_at < validity.valid_until)
      end

      def scope_matches?(scope, context)
        scalar_matches?(scope.workspace_id, context.workspace_id) &&
          collection_matches?(scope.repository_ids, context.repository_id) &&
          scalar_matches?(scope.change_set_id, context.change_set_id) &&
          scalar_matches?(scope.work_item_id, context.work_item_id) &&
          scalar_matches?(scope.attempt_id, context.attempt_id) &&
          collection_overlaps?(scope.path_selectors, context.paths) &&
          collection_matches?(scope.environments, context.environment) &&
          collection_matches?(scope.agent_roles, context.agent_role)
      end

      def conditions_match?(conditions, context)
        collection_matches?(conditions.phases, context.phase) &&
          collection_matches?(conditions.languages, context.language) &&
          collection_matches?(conditions.environments, context.environment)
      end

      def scalar_matches?(constraint, value)
        !constraint || constraint == value
      end

      def collection_matches?(constraints, value)
        constraints.empty? || (value && constraints.include?(value))
      end

      def collection_overlaps?(constraints, values)
        constraints.empty? || constraints.any? { values.include?(_1) }
      end

      def resolved_decision(head, definition, document)
        anchor_kind, anchor_rank = anchor(document.scope)
        ResolvedDecisionV1.new(
          head:,
          definition_digest: definition.digest,
          topic_id: document.topic.topic_id,
          effect: document.effect,
          modality: document.modality,
          value: document.value,
          enforcement: document.enforcement,
          anchor_kind:,
          anchor_rank:,
          applicability_reasons: APPLICABILITY_REASONS
        )
      end

      def anchor(scope)
        kind = if scope.attempt_id
                 "attempt"
        elsif scope.work_item_id
                 "work_item"
        elsif scope.change_set_id
                 "change_set"
        elsif !scope.repository_ids.empty?
                 "repository"
        else
                 "workspace"
        end
        [ kind, ANCHOR_RANKS.fetch(kind) ]
      end

      def build_result(resolved:, unsupported_dimensions:, unsupported_decisions:, unresolved_decisions:)
        ordered = resolved.sort_by { [ _1.head.decision_id.b, _1.head.event.event_id.b ] }
        highest_rank = ordered.map(&:anchor_rank).max
        highest = highest_rank ? ordered.select { _1.anchor_rank == highest_rank } : []
        lower = highest_rank ? ordered.reject { _1.anchor_rank == highest_rank } : []
        conflict = if highest.length > 1
                     ConflictV1.new(decisions: highest, reason: "tied_most_specific")
        end
        effective = highest.length == 1 ? highest.sole : nil
        shadowed = lower.map do |decision|
          ShadowedDecisionV1.new(decision:, reason: "less_specific")
        end

        ResultV1.new(
          effective_decision: effective,
          shadowed_decisions: shadowed,
          conflict:,
          unsupported_dimensions:,
          unsupported_decisions:,
          unresolved_decisions:
        )
      end
    end
  end
end
