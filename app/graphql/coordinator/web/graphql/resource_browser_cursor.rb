# frozen_string_literal: true

module Coordinator::Web::Graphql
  class ResourceBrowserCursor
    SCHEMA = "project-resource-cursor/v3"
    KINDS = %w[resources active-leases].freeze

    def self.encode(kind, filters:, cursor:)
      validate_kind!(kind)
      document = canonical(
        "schema" => SCHEMA,
        "kind" => kind,
        "filters" => filters,
        "cursor" => cursor
      )
      Base64.urlsafe_encode64(JSON.generate(document), padding: false)
    end

    def self.decode(value, kind, filters:)
      return unless value

      validate_kind!(kind)
      payload = JSON.parse(Base64.urlsafe_decode64(value))
      cursor = payload.fetch("cursor")
      valid = payload.keys.sort == %w[cursor filters kind schema] &&
        payload.fetch("schema") == SCHEMA &&
        payload.fetch("kind") == kind &&
        payload.fetch("filters") == canonical(filters) &&
        valid_cursor?(cursor, kind) &&
        encode(kind, filters:, cursor:) == value
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid" unless valid

      cursor
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError, NoMethodError
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid"
    end

    def self.valid_cursor?(cursor, kind)
      keys = kind == "active-leases" ? %w[after_id after_updated_at as_of] : %w[after_id after_updated_at]
      valid = cursor.keys.sort == keys &&
        Coordinator::Shared::Types::UUID_V7_PATTERN.match?(cursor.fetch("after_id", "")) &&
        Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(cursor.fetch("after_updated_at", ""))
      valid &&= Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(cursor.fetch("as_of", "")) if
        kind == "active-leases"
      valid
    end
    private_class_method :valid_cursor?

    def self.canonical(value)
      case value
      when Hash
        value.to_h { |key, nested| [ key.to_s, canonical(nested) ] }.sort.to_h
      when Array
        value.map { canonical(_1) }
      else
        value
      end
    end
    private_class_method :canonical

    def self.validate_kind!(kind)
      raise InvalidCursor, "#{kind} cursor is invalid" unless KINDS.include?(kind)
    end
    private_class_method :validate_kind!
  end
end
