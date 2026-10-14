# frozen_string_literal: true

module Coordinator::Read::Repositories
  # Rails adapter glue; only the pure ColumnPatches contract is covered by RBS.
  # Complete insert-if-absent rows precede selective, compatible UPDATE masks.
  class BatchWriter
    MAXIMUM_STATEMENT_BYTES = 1_048_576

    def initialize(model:, patches:)
      @model, @patches = model, patches
    end

    def call
      return if @patches.empty?

      @model.connection_pool.with_connection do |connection|
        connection.transaction do
          @patches.inserts.group_by { _1.keys.sort }.each_value { insert_group(_1, connection:) }
          @patches.update_groups.each { update_group(_1, connection:) }
        end
      end
      nil
    end

    private

    def insert_group(rows, connection:)
      columns = rows.first.keys
      each_chunk(rows, columns:, connection:) do |chunk|
        @model.insert_all(chunk.map(&:first), unique_by: @patches.identity_columns, record_timestamps: false)
      end
    end

    def update_group(group, connection:)
      columns = @patches.identity_columns + group.columns
      aliases = columns.map { quote_column(_1, connection:) }.join(", ")
      assignments = group.columns.map do |column|
        quoted = quote_column(column, connection:)
        value = column == :updated_at ? "GREATEST(target.#{quoted}, patch.#{quoted})" : "patch.#{quoted}"
        "#{quoted} = #{value}"
      end.join(", ")
      identity = @patches.identity_columns.map do |column|
        quoted = quote_column(column, connection:)
        "target.#{quoted} = patch.#{quoted}"
      end.join(" AND ")
      prefix = "UPDATE #{connection.quote_table_name(@model.table_name)} AS target SET #{assignments} FROM (VALUES "
      suffix = ") AS patch(#{aliases}) WHERE #{identity}"
      each_chunk(group.rows, columns:, connection:, overhead: prefix.bytesize + suffix.bytesize) do |chunk|
        connection.execute(prefix + chunk.map(&:last).join(", ") + suffix)
      end
    end

    # Cache each quoted row once. A large individual row is never rejected by
    # the technical chunk budget; it occupies its own statement.
    def each_chunk(rows, columns:, connection:, overhead: 0)
      chunk, bytes = [], overhead
      rows.each do |row|
        encoded = quoted_row(row, columns:, connection:)
        size = encoded.bytesize + 2
        if chunk.any? && bytes + size > MAXIMUM_STATEMENT_BYTES
          yield chunk
          chunk, bytes = [], overhead
        end
        chunk << [ row, encoded ]
        bytes += size
      end
      yield chunk if chunk.any?
    end

    def quoted_row(row, columns:, connection:)
      "(" + columns.map do |column|
        definition = @model.columns_hash.fetch(column.to_s)
        value = @model.type_for_attribute(column.to_s).serialize(row.fetch(column))
        "CAST(#{connection.quote(value)} AS #{definition.sql_type})"
      end.join(", ") + ")"
    end

    def quote_column(column, connection:)
      @model.columns_hash.fetch(column.to_s)
      connection.quote_column_name(column)
    end
  end
end
