# frozen_string_literal: true

module Coordinator::Read::Search
  class SourceCatalog
    def initialize(artifact_sources: ArtifactSources.new)
      @artifact_sources = artifact_sources
    end

    def call(field)
      return @artifact_sources.call(field) if field.entity_type == "development_artifact"

      [ public_send(field.entity_type, field) ]
    end

    def skill(field)
      owner = %w[name scope].include?(field.column) ? "s" : "revision"
      table, row_id = owner == "s" ? [ "skills", "s.skill_id" ] : [ "skill_revisions", "revision.id::text" ]
      build(field, table:, from: "skills s JOIN skill_revisions revision ON revision.skill_id = s.skill_id AND revision.revision = s.revision",
        row_id:, owner:, identity: "s.skill_id", entity_id: "s.skill_id", updated_at: "s.updated_at",
        scope: "s.scope", direct_scope: true, membership: "repository.scope = s.scope",
        retrieval: "jsonb_build_object('tool', 'skill_get', 'arguments', jsonb_build_object('name', s.name, 'scope', s.scope, 'revision', s.revision))")
    end

    def skill_asset(field)
      build(field, table: "skill_assets", from: "skill_assets a JOIN skills s ON s.skill_id = a.skill_id AND s.revision = a.revision",
        row_id: "a.id::text", owner: "a", identity: "a.skill_id || ':' || a.revision::text || ':' || a.path", entity_id: "a.skill_id",
        updated_at: "a.updated_at", scope: "s.scope", direct_scope: true, membership: "repository.scope = s.scope",
        condition: field.column == "content_text" ? "a.content_encoding = 'utf-8'" : "TRUE",
        retrieval: "jsonb_build_object('tool', 'skill_asset_get', 'arguments', jsonb_build_object('name', s.name, 'scope', s.scope, 'path', a.path, 'revision', a.revision))")
    end

    def resource(field)
      build(field, table: "resources", from: "resources r", row_id: "r.resource_id", owner: "r",
        identity: "r.resource_id", entity_id: "r.resource_id", updated_at: "r.updated_at", repository_id: "r.repository_id",
        membership: "repository.repository_id = r.repository_id",
        retrieval: "jsonb_build_object('tool', 'resource_get', 'arguments', jsonb_build_object('resource_id', r.resource_id))")
    end

    def guidance(field)
      build(field, table: "user_utterances", from: "user_utterances g", row_id: "g.message_id", owner: "g",
        identity: "g.message_id", entity_id: "g.message_id", updated_at: "g.updated_at", membership: guidance_membership,
        retrieval: "jsonb_build_object('tool', 'guidance_get', 'arguments', jsonb_build_object('message_id', g.message_id))")
    end

    def agent_choice(field)
      build(field, table: "agent_choices", from: "agent_choices choice", row_id: "choice.choice_id", owner: "choice",
        identity: "choice.choice_id", entity_id: "choice.choice_id", updated_at: "choice.updated_at",
        repository_id: "choice.context ->> 'repository_id'", membership: "repository.repository_id = choice.context ->> 'repository_id'",
        retrieval: "jsonb_build_object('tool', 'agent_choice_get', 'arguments', jsonb_build_object('choice_id', choice.choice_id))")
    end

    def decision(field)
      build(field, table: "decision_definitions", from: "decision_definitions decision", row_id: "decision.decision_id", owner: "decision",
        identity: "decision.decision_id", entity_id: "decision.decision_id", updated_at: "decision.updated_at",
        membership: "EXISTS (SELECT 1 FROM decision_repository_memberships membership WHERE membership.decision_id = decision.decision_id AND membership.repository_id = repository.repository_id)",
        retrieval: "jsonb_build_object('tool', 'decision_get', 'arguments', jsonb_build_object('decision_id', decision.decision_id))")
    end

    def work_item(field)
      build(field, table: "coordinator_contexts",
        from: "coordinator_contexts c JOIN coordination_dashboard_work_items w ON w.change_set_id = c.change_set_id",
        row_id: "c.change_set_id", owner: "w", identity: "w.work_item_id", entity_id: "w.work_item_id", updated_at: "c.updated_at",
        repository_id: "w.repository_id", membership: "repository.repository_id = w.repository_id",
        retrieval: "jsonb_build_object('tool', 'coord_context', 'arguments', jsonb_build_object('change_set_id', w.change_set_id, 'work_item_id', w.work_item_id))")
    end

    private

    def build(field, table:, from:, row_id:, owner:, identity:, entity_id:, updated_at:, membership:, retrieval:,
      scope: "NULL::text", repository_id: "NULL::text", direct_scope: false, condition: "TRUE")
      multiple = field.values != "scalar" || field.path.include?("*") || field.entity_type == "work_item"
      if multiple
        from += " JOIN coordinator_search_values sv ON sv.source_table = '#{table}' AND sv.source_id = #{row_id} AND sv.field = '#{field.selector}'"
        from += " AND sv.document_id = w.work_item_id" if field.entity_type == "work_item"
      end
      path = field.path.empty? ? "#{owner}.#{field.column}" : "#{owner}.#{field.column} #>> '{#{field.path.join(',')}}'"
      Source.new(table:, from:, row_id:, identity:, entity_id:, updated_at:, scope:, repository_id:, membership:, direct_scope:,
        value: multiple ? "sv.value" : path,
        path: multiple ? "to_jsonb(sv.value_path)" : "jsonb_build_array(#{([ field.column ] + field.path).map { "'#{_1}'" }.join(',')})",
        condition:, multiple_values: multiple, retrieval:,
        provenance: "jsonb_build_object('source_table', '#{table}', 'source_id', #{row_id})")
    end

    def guidance_membership
      <<~SQL.squish
        (COALESCE(g.anchors -> 'repository_ids', '[]'::jsonb) ? repository.repository_id
        OR EXISTS (SELECT 1 FROM coordination_dashboard_work_items anchor
          WHERE anchor.repository_id = repository.repository_id AND
            (anchor.change_set_id = g.anchors ->> 'change_set_id' OR anchor.work_item_id = g.anchors ->> 'work_item_id'))
        OR EXISTS (SELECT 1 FROM attempt_histories attempt
          JOIN coordination_dashboard_work_items anchor ON anchor.change_set_id = attempt.change_set_id AND anchor.work_item_id = attempt.work_item_id
          WHERE anchor.repository_id = repository.repository_id AND attempt.attempt_id = g.anchors ->> 'attempt_id'))
      SQL
    end
  end
end
