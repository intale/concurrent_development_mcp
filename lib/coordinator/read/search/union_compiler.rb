# frozen_string_literal: true

module Coordinator::Read::Search
  class UnionCompiler
    # The input is already bounded by at most eight field branches, each N+1.
    # Keep the final merge a small independent query, not one large source view.
    def call(rows, limit:)
      sql = <<~SQL
        SELECT entity_type, document_id, updated_at, document::text, matches::text
        FROM (
          SELECT entity_type, document_id,
            max((document ->> 'updated_at')::timestamp) AS updated_at,
            (jsonb_agg(document ORDER BY evidence ->> 'field') -> 0) AS document,
            jsonb_agg(evidence ORDER BY evidence ->> 'field') AS matches
          FROM jsonb_to_recordset($1::jsonb) AS candidate(
            entity_type text, document_id text, document jsonb, evidence jsonb)
          GROUP BY entity_type, document_id
        ) canonical_union
        ORDER BY #{FieldQueryCompiler::ORDER}
        LIMIT #{limit + 1}
      SQL
      SqlFragment.new(sql:, binds: [ JSON.generate(rows.map { _1.slice("entity_type", "document_id", "document", "evidence") }) ])
    end
  end
end
