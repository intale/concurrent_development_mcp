# frozen_string_literal: true

module Coordinator::Mcp
  class DevelopmentSearchSchema
    def call
      limits = Coordinator::Read::Search::Limits
      schema = Schemas.object_schema(properties: {
        combine: { const: "or", description: "Selected fields combine by canonical OR/union only, never intersection." },
        fields: { type: "array", minItems: 1, maxItems: limits::FIELDS, uniqueItems: true,
          description: "Choose each selector once. Each complete Boolean expression matches one raw scalar; nested strings are not combined.",
          items: Schemas.object_schema(properties: {
            field: { type: "string", enum: Coordinator::Read::Search::FieldCatalog::SELECTORS,
              description: "Exact approved projection field. Content is full UTF-8 text; binary content is not decoded. Resource bodies are not projected." },
            query: { "$ref" => "#/$defs/expression1" }
          }, required: %w[field query]) },
        filters: Schemas.object_schema(properties: {
          scope: { type: "string", minLength: 1, maxLength: 500, "x-maxBytes": 500,
            description: "Exact scope; intersects Repository membership. No implicit hierarchy or global inclusion." },
          repository_id: Schemas.uuid_v7.merge(description: "Exact registered Repository membership, intersected with every other filter."),
          entity_types: { type: "array", minItems: 1, maxItems: 8, uniqueItems: true,
            items: { type: "string", enum: Coordinator::Read::Search::FieldCatalog::ENTITY_TYPES } }
        }, required: []),
        limit: { type: "integer", minimum: 1, maximum: limits::PAGE, default: limits::DEFAULT_PAGE,
          description: "Mandatory server caps apply to every source/field branch and the final union; a separate N+1 lookahead is also bounded." },
        cursor: { type: "string", minLength: 1, maxLength: limits::CURSOR_BYTES, "x-maxBytes": limits::CURSOR_BYTES,
          description: "Opaque server cursor for these exact matching expressions and filters. Omit on the first page; page size may change. Live pages are not a retained snapshot." }
      }, required: [ "fields" ])
      schema.merge("$defs": definitions, "x-maxBytes": limits::INPUT_BYTES,
        description: "Literal pattern search only. Every Boolean alternative needs a positive literal with three consecutive alphanumeric characters. NOT is an exclusion inside AND/OR, never an independent query. Runtime also bounds total expression nodes and bytes.")
    end

    private

    def definitions
      limits = Coordinator::Read::Search::Limits
      definitions = { "literal" => Schemas.object_schema(properties: {
        match: { type: "string", enum: %w[contains starts_with ends_with equals],
          description: "equals matches the entire scalar, not an array membership or a substring." },
        value: { type: "string", minLength: 3, maxLength: limits::LITERAL_CHARACTERS, "x-maxBytes": limits::LITERAL_BYTES,
          "x-encoding": "UTF-8", description: "Ordinary UTF-8 literal. Percent, underscore, backslash and regex characters have no special syntax; the server escapes them." },
        case_sensitive: { type: "boolean", default: true }
      }, required: %w[match value]) }
      (1..limits::DEPTH).each do |depth|
        alternatives = [ { "$ref" => "#/$defs/literal" } ]
        if depth < limits::DEPTH
          alternatives << boolean_schema(depth, %w[and or], minimum: 2, maximum: limits::OPERANDS)
          alternatives << boolean_schema(depth, [ "not" ], minimum: 1, maximum: 1) unless depth == 1
        end
        definitions["expression#{depth}"] = { oneOf: alternatives }
      end
      definitions
    end

    def boolean_schema(depth, operators, minimum:, maximum:)
      Schemas.object_schema(properties: {
        operator: { type: "string", enum: operators },
        operands: { type: "array", minItems: minimum, maxItems: maximum,
          items: { "$ref" => "#/$defs/expression#{depth + 1}" } }
      }, required: %w[operator operands])
    end
  end
end
