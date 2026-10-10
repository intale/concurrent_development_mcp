# frozen_string_literal: true

module Coordinator::Read::Search
  class QueryBuilder
    include Dry::Monads[:result]

    def initialize(cursor_codec:, contract: Coordinator::Read::Contracts::DevelopmentSearch.new)
      @cursor_codec = cursor_codec
      @contract = contract
    end

    def call(input)
      validated = @contract.call(input)
      return Failure(Problem.new(code: "invalid_input", message: "Development search input is invalid", details: validated.errors.to_h)) if validated.failure?

      values = validated.to_h
      fields = values.fetch(:fields).map do |branch|
        Branch.new(field: FieldCatalog.fetch(branch.fetch(:field)), expression: build_node(branch.fetch(:query)))
      end.sort_by { _1.field.selector }
      supplied_filters = values.fetch(:filters, {})
      filters = Filters.new(scope: supplied_filters[:scope], repository_id: supplied_filters[:repository_id],
        entity_types: supplied_filters.fetch(:entity_types, []).sort)
      fingerprint = @cursor_codec.fingerprint(fields:, filters:)
      boundary = @cursor_codec.decode(values[:cursor], fingerprint:) if values[:cursor]
      Success(Query.new(fields:, filters:, fingerprint:, boundary:, limit: values.fetch(:limit, Limits::DEFAULT_PAGE)))
    rescue CursorCodec::InvalidCursor => error
      Failure(Problem.new(code: "invalid_cursor", message: error.message, details: {}))
    end

    private

    def build_node(input)
      Node.new(operator: input[:operator], operands: input.fetch(:operands, []).map { build_node(_1) },
        match: input[:match], value: input[:value], case_sensitive: input.fetch(:case_sensitive, true))
    end
  end
end
