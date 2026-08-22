# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Interpretations
      class ScopeResolver
        Result = Data.define(:scope, :provenance)

        def call(submitted_scope:, source:)
          return explicit(submitted_scope, source.message_id) if submitted_scope

          inferred(source)
        end

        private

        def explicit(scope, message_id)
          Result.new(
            scope:,
            provenance: Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
              kind: "explicit",
              anchor_level: anchor_level(scope),
              source_message_id: message_id
            )
          )
        end

        def inferred(source)
          anchors = source.anchors
          level = inferred_level(anchors)
          kind = level == "unresolved" ? "unresolved" : "inferred"

          Result.new(
            scope: scope_from_anchors(anchors, level:),
            provenance: Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
              kind:,
              anchor_level: level,
              source_message_id: source.message_id
            )
          )
        end

        def inferred_level(anchors)
          return "attempt" if anchors.attempt_id
          return "work_item" if anchors.work_item_id
          return "change_set" if anchors.change_set_id
          return "repository" if anchors.repository_ids.one?

          "unresolved"
        end

        def anchor_level(scope)
          return "attempt" if scope.attempt_id
          return "work_item" if scope.work_item_id
          return "change_set" if scope.change_set_id
          return "repository" unless scope.repository_ids.empty?
          return "workspace" if scope.workspace_id

          "unresolved"
        end

        def scope_from_anchors(anchors, level:)
          Coordinator::Write::Interpretations::DecisionScopeV1.new(
            workspace_id: nil,
            repository_ids: level == "unresolved" ? [] : anchors.repository_ids,
            branch_selectors: [],
            change_set_id: anchors.change_set_id,
            work_item_id: anchors.work_item_id,
            attempt_id: anchors.attempt_id,
            candidate_id: nil,
            path_selectors: [],
            symbol_selectors: [],
            contract_selectors: [],
            schema_selectors: [],
            environments: [],
            agent_roles: []
          )
        end
      end
    end
  end
end
