# frozen_string_literal: true

module Coordinator::Web::Graphql
  class DashboardCursor
    SCHEMA = "coordination-cursor/v2"
    KINDS = %w[change-sets work-items dependencies].freeze

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
      expected_filters = canonical(filters)
      cursor = payload.fetch("cursor")
      valid = payload.keys.sort == %w[cursor filters kind schema] &&
        payload.fetch("schema") == SCHEMA &&
        payload.fetch("kind") == kind &&
        payload.fetch("filters") == expected_filters &&
        cursor.keys.sort == %w[id sort_value] &&
        cursor.fetch("id").is_a?(String) &&
        !cursor.fetch("id").empty? &&
        (cursor.fetch("sort_value").nil? || cursor.fetch("sort_value").is_a?(String)) &&
        encode(kind, filters:, cursor:) == value
      raise InvalidCursor, "#{kind} cursor is invalid" unless valid

      cursor
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError, NoMethodError
      raise InvalidCursor, "#{kind} cursor is invalid"
    end

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
