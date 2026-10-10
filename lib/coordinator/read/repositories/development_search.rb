# frozen_string_literal: true

module Coordinator::Read
  class Repositories::DevelopmentSearch
    include Dry::Monads[:result]

    def initialize(cursor_codec:, compiler: Search::FieldQueryCompiler.new, union: Search::UnionCompiler.new, merger: Search::PageMerger.new(cursor_codec:))
      @compiler = compiler
      @union = union
      @merger = merger
    end

    def page(query)
      budget = Search::ExecutionBudget.new
      page = ApplicationRecord.connection_pool.with_connection do |connection|
        connection.transaction(isolation: :repeatable_read) do
          connection.execute("SET TRANSACTION READ ONLY")
          rows = query.fields.flat_map do |branch|
            next [] if query.filters.entity_types.any? && !query.filters.entity_types.include?(branch.field.entity_type)

            fragment = @compiler.call(branch, query:)
            execute(connection, fragment, budget).map do |row|
              row.merge("document" => JSON.parse(row.fetch("document")), "evidence" => JSON.parse(row.fetch("evidence")))
            end
          end
          merged = execute(connection, @union.call(rows, limit: query.limit), budget).map do |row|
            row.merge("document" => JSON.parse(row.fetch("document")), "matches" => JSON.parse(row.fetch("matches")))
          end
          @merger.call(merged, query:)
        end
      end
      budget.check!
      response_bytes = JSON.generate(page.to_h).bytesize
      budget.check!
      if response_bytes > Search::Limits::RESPONSE_BYTES
        return Failure(Search::Problem.new(code: "search_response_limit", message: "Search response exceeds the byte limit; reduce the page size", details: {}))
      end
      Success(page)
    rescue Search::ExecutionBudget::Exceeded, ActiveRecord::QueryCanceled
      Failure(Search::Problem.new(code: "search_budget_exceeded", message: "Search exceeded its execution budget; narrow the query and retry", details: {}))
    end

    private

    def execute(connection, fragment, budget)
      connection.execute("SET LOCAL statement_timeout = #{budget.statement_milliseconds}")
      bindings = fragment.binds.each_with_index.map do |value, index|
        ActiveRecord::Relation::QueryAttribute.new("search_#{index}", value, ActiveRecord::Type::String.new)
      end
      connection.exec_query(fragment.sql, "Development search", bindings).to_a
    end
  end
end
