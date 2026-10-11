# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class SqlStatement
      INPUT_BYTE_LIMIT = 32768
      TEXT_CHARACTER_LIMIT = 2048
      # Conservative: even a delimiter inside a literal is grounds for omission.
      # Numeric PostgreSQL placeholders ($1, $2, ...) remain supported.
      DOLLAR_QUOTE = /\$(?!\d)[^$]*\$/

      class << self
        def operation(sql)
          name = sql.lstrip[/\A[A-Za-z]+/]&.upcase
          Contract::SQL_OPERATIONS.include?(name) ? name : "OTHER"
        end

        def text(sql)
          return nil if sql.bytesize > INPUT_BYTE_LIMIT || DOLLAR_QUOTE.match?(sql)

          sanitized = OpenTelemetry::Helpers::SqlProcessor.obfuscate_sql(sql, adapter: :postgres, obfuscation_limit: INPUT_BYTE_LIMIT)
          return nil if sanitized.nil? || sanitized.start_with?("SQL not obfuscated", "Failed to obfuscate")

          sanitized.slice(0, TEXT_CHARACTER_LIMIT)
        end
      end
    end
  end
end
