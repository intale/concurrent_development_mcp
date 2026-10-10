# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DevelopmentSearch < Dry::Validation::Contract
      config.validate_keys = true

      json do
        optional(:combine).filled(:string, eql?: "or")
        required(:fields).value(:array, min_size?: 1, max_size?: Search::Limits::FIELDS).each(:hash) do
          required(:field).filled(:string, included_in?: Search::FieldCatalog::SELECTORS)
          required(:query).hash(Search::NodeSchema.build)
        end
        optional(:filters).hash do
          optional(:scope).filled(:string, max_size?: 500)
          optional(:repository_id).filled(:string, format?: Types::UUID_V7_PATTERN)
          optional(:entity_types).value(:array, min_size?: 1, max_size?: 8).each(:string, included_in?: Search::FieldCatalog::ENTITY_TYPES)
        end
        optional(:limit).filled(:integer, gteq?: 1, lteq?: Search::Limits::PAGE)
        optional(:cursor).filled(:string, max_size?: Search::Limits::CURSOR_BYTES)
      end

      rule(:fields) do
        selectors = value.map { _1.fetch(:field) }
        key.failure("field selectors must be distinct") unless selectors.uniq == selectors
        count = 0
        value.each_with_index do |branch, index|
          result = Search::ExpressionValidator.new.call(branch.fetch(:query))
          count += result.node_count
          result.issues.each do |issue|
            key([ :fields, index, :query ] + issue.path).failure(issue.message)
          end
        end
        key.failure("request exceeds #{Search::Limits::REQUEST_NODES} expression nodes") if count > Search::Limits::REQUEST_NODES
      end

      rule(:filters) do
        next unless value

        if value[:scope] && (value[:scope].encoding != Encoding::UTF_8 || !value[:scope].valid_encoding? || value[:scope].include?("\0"))
          key.failure("scope must be valid UTF-8 text without NUL characters")
        end
        key.failure("scope must be at most 500 UTF-8 bytes") if value[:scope] && value[:scope].bytesize > 500
        next unless value[:entity_types]

        types = value[:entity_types]
        key.failure("entity types must be distinct") unless types.uniq == types
      end

      rule(:cursor) do
        key.failure("cursor exceeds the byte limit") if value && value.bytesize > Search::Limits::CURSOR_BYTES
      end

      rule do
        if JSON.generate(values.to_h).bytesize > Search::Limits::INPUT_BYTES
          key.failure("input must be at most #{Search::Limits::INPUT_BYTES} UTF-8 bytes")
        end
      end
    end
  end
end
