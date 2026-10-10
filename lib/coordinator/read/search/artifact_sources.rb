# frozen_string_literal: true

module Coordinator::Read::Search
  class ArtifactSources
    PROPERTIES = %w[scope title kind labels source_kind source_locator source_revision
      source_observed_at source_collector content_encoding content_media_type content_text
      content_base64 content_byte_size].freeze
    LATEST_ORDER = "observed_global_position DESC NULLS LAST, observation_id DESC"

    def call(field)
      sources = [ observation(field) ]
      sources.unshift(head(field)) unless field.column == "classification_reason"
      sources
    end

    private

    def head(field)
      equivalent = equality("h", "latest")
      from = <<~SQL.squish
        development_artifacts h
        LEFT JOIN LATERAL (
          SELECT o.* FROM development_artifact_observations o
          WHERE o.artifact_id = h.artifact_id ORDER BY #{LATEST_ORDER} LIMIT 1
        ) latest ON TRUE
      SQL
      source(field, table: "development_artifacts", from:, row_id: "h.artifact_id",
        identity: "'current:' || h.artifact_id", entity_id: "h.artifact_id", scope: "h.scope",
        updated_at: "CASE WHEN #{equivalent} THEN GREATEST(h.updated_at, latest.updated_at) ELSE h.updated_at END",
        owner: "h", observation_id: "CASE WHEN #{equivalent} THEN latest.observation_id ELSE NULL END")
    end

    def observation(field)
      equivalent = "latest.observation_id = o.observation_id AND #{equality('h', 'o')}"
      from = <<~SQL.squish
        development_artifact_observations o
        LEFT JOIN development_artifacts h ON h.artifact_id = o.artifact_id
        LEFT JOIN LATERAL (
          SELECT candidate.observation_id FROM development_artifact_observations candidate
          WHERE candidate.artifact_id = o.artifact_id ORDER BY #{LATEST_ORDER} LIMIT 1
        ) latest ON TRUE
      SQL
      source(field, table: "development_artifact_observations", from:, row_id: "o.observation_id",
        identity: "CASE WHEN #{equivalent} THEN 'current:' || o.artifact_id ELSE 'observation:' || o.observation_id END",
        entity_id: "o.artifact_id", scope: "o.scope",
        updated_at: "CASE WHEN #{equivalent} THEN GREATEST(h.updated_at, o.updated_at) ELSE o.updated_at END",
        owner: "o", observation_id: "o.observation_id")
    end

    def equality(left, right)
      "#{left}.artifact_id IS NOT NULL AND #{right}.observation_id IS NOT NULL AND " \
        "ROW(#{PROPERTIES.map { "#{left}.#{_1}" }.join(',')}) IS NOT DISTINCT FROM " \
        "ROW(#{PROPERTIES.map { "#{right}.#{_1}" }.join(',')})"
    end

    def source(field, table:, from:, row_id:, identity:, entity_id:, scope:, updated_at:, owner:, observation_id:)
      multiple = field.values != "scalar"
      if multiple
        from += " JOIN coordinator_search_values sv ON sv.source_table = '#{table}' AND sv.source_id = #{row_id} AND sv.field = '#{field.selector}'"
      end
      condition = field.column == "content_text" ? "#{owner}.content_encoding = 'utf-8'" : "TRUE"
      Source.new(table:, from:, row_id:, identity:, entity_id:, scope:, updated_at:,
        repository_id: "NULL::text", membership: "repository.scope = #{scope}", direct_scope: true,
        value: multiple ? "sv.value" : "#{owner}.#{field.column}",
        path: multiple ? "to_jsonb(sv.value_path)" : "jsonb_build_array('#{field.column}')",
        condition:, multiple_values: multiple,
        retrieval: "CASE WHEN #{entity_id} IS NULL THEN NULL ELSE jsonb_build_object('tool', 'development_artifact_content_get', " \
          "'arguments', jsonb_strip_nulls(jsonb_build_object('artifact_id', #{entity_id}, 'observation_id', #{observation_id}))) END",
        provenance: "jsonb_strip_nulls(jsonb_build_object('source_table', '#{table}', 'source_id', #{row_id}, " \
          "'observation_id', #{observation_id}, 'source_kind', #{owner}.source_kind, 'source_locator', #{owner}.source_locator, " \
          "'source_revision', #{owner}.source_revision))")
    end
  end
end
