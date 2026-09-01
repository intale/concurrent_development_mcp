# frozen_string_literal: true

module Coordinator::Web::Graphql
  class GovernanceBrowserCursor
    SCHEMA = "project-governance-cursor/v2"
    KINDS = %w[decisions guidance choices impacts interpretations receipts].freeze

    def self.encode(kind, filters:, cursor:)
      validate_kind!(kind)
      Base64.urlsafe_encode64(
        JSON.generate(canonical("schema" => SCHEMA, "kind" => kind, "filters" => filters, "cursor" => cursor)),
        padding: false
      )
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
        valid_cursor?(kind, cursor) &&
        encode(kind, filters:, cursor:) == value
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid" unless valid

      cursor
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError, NoMethodError
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid"
    end

    def self.valid_cursor?(kind, cursor)
      case kind
      when "decisions", "guidance", "choices", "receipts"
        cursor.is_a?(String) && Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(cursor)
      when "impacts"
        cursor.is_a?(Hash) && cursor.keys.sort == %w[assessment_id global_position] &&
          cursor.fetch("global_position", nil).is_a?(Integer) && cursor.fetch("global_position") >= 0 &&
          Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(cursor.fetch("assessment_id", ""))
      when "interpretations"
        cursor.is_a?(Integer) && cursor >= -1
      else
        false
      end
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
