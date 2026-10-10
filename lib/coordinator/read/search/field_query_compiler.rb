# frozen_string_literal: true

module Coordinator::Read::Search
  class FieldQueryCompiler
    ORDER = 'updated_at DESC, entity_type COLLATE "C", document_id COLLATE "C"'.freeze

    def initialize(sources: SourceCatalog.new, expressions: ExpressionCompiler.new)
      @sources = sources
      @expressions = expressions
    end

    def call(branch, query:)
      binds = []
      parts = @sources.call(branch.field).map do |source|
        source_query(source, branch:, query:, binds:)
      end
      # Even the two physical Artifact sources are independently capped. Their
      # canonical union deduplicates before this field branch's final cap.
      union = parts.map { "(#{_1})" }.join(" UNION ALL ")
      deduplicated = <<~SQL
        SELECT DISTINCT ON (document_id COLLATE "C") * FROM (#{union}) field_candidates
        ORDER BY document_id COLLATE "C", source_priority
      SQL
      SqlFragment.new(sql: "SELECT entity_type, document_id, updated_at, source_priority, document::text, evidence::text " \
        "FROM (#{deduplicated}) canonical_field ORDER BY #{ORDER} LIMIT #{query.limit + 1}", binds:)
    end

    private

    def source_query(source, branch:, query:, binds:)
      predicate = @expressions.call(branch.expression, column: source.value, offset: binds.length)
      binds.concat(predicate.binds)
      position = @expressions.excerpt_position(branch.expression, column: source.value, offset: binds.length)
      binds.concat(position.binds)
      excerpt_start = "GREATEST(1, (#{position.sql}) - 60)"
      conditions = [ source.condition, "(#{predicate.sql})" ]
      conditions.concat(filter_conditions(source, query.filters, binds))
      conditions << cursor_condition(source, branch.field.entity_type, query.boundary, binds) if query.boundary
      projected = <<~SQL
        SELECT '#{branch.field.entity_type}'::text AS entity_type,
          #{source.identity} AS document_id, #{source.updated_at} AS updated_at,
          #{source.table == 'development_artifact_observations' ? 0 : 1} AS source_priority,
          jsonb_build_object('entity_type', '#{branch.field.entity_type}', 'document_id', #{source.identity},
            'entity_id', #{source.entity_id}, 'updated_at', to_char(#{source.updated_at}, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'scope', #{result_scope(source, query.filters, binds)}, 'repository_id', #{result_repository(source, query.filters, binds)},
            'retrieval', #{source.retrieval}, 'provenance', #{source.provenance}) AS document,
          jsonb_build_object('field', '#{branch.field.selector}', 'path', #{source.path},
            'excerpt', substring(#{source.value} FROM #{excerpt_start} FOR #{Limits::EXCERPT_CHARACTERS}),
            'excerpt_offset', #{excerpt_start} - 1) AS evidence
        FROM #{source.from} WHERE #{conditions.join(' AND ')}
      SQL
      if source.multiple_values
        projected = "SELECT DISTINCT ON (document_id COLLATE \"C\") * FROM (#{projected}) raw_values " \
          "ORDER BY document_id COLLATE \"C\", (evidence -> 'path')::text COLLATE \"C\""
      end
      "SELECT * FROM (#{projected}) matched_source ORDER BY #{ORDER} LIMIT #{query.limit + 1}"
    end

    def filter_conditions(source, filters, binds)
      conditions = []
      membership_filters = []
      if filters.scope
        placeholder = bind(binds, filters.scope)
        if source.direct_scope
          conditions << "#{source.scope} = #{placeholder}"
        else
          membership_filters << "repository.scope = #{placeholder}"
        end
      end
      if filters.repository_id
        membership_filters << "repository.repository_id = #{bind(binds, filters.repository_id)}"
      end
      unless membership_filters.empty?
        conditions << "EXISTS (SELECT 1 FROM repositories repository WHERE #{membership_filters.join(' AND ')} AND (#{source.membership}))"
      end
      conditions
    end

    def cursor_condition(source, entity_type, boundary, binds)
      time = bind(binds, boundary.updated_at)
      type = bind(binds, boundary.entity_type)
      id = bind(binds, boundary.document_id)
      <<~SQL.squish
        (#{source.updated_at} < #{time}::timestamp OR (#{source.updated_at} = #{time}::timestamp AND
          ('#{entity_type}' COLLATE "C" > #{type} COLLATE "C" OR
          ('#{entity_type}' = #{type} AND (#{source.identity}) COLLATE "C" > #{id} COLLATE "C"))))
      SQL
    end

    def bind(binds, value)
      binds << value
      "$#{binds.length}"
    end

    def result_scope(source, filters, binds)
      return "#{bind(binds, filters.scope)}::text" if filters.scope
      return source.scope if source.direct_scope
      return "NULL::text" if source.repository_id == "NULL::text"

      "(SELECT associated.scope FROM repositories associated WHERE associated.repository_id = #{source.repository_id} LIMIT 1)"
    end

    def result_repository(source, filters, binds)
      filters.repository_id ? "#{bind(binds, filters.repository_id)}::text" : source.repository_id
    end
  end
end
