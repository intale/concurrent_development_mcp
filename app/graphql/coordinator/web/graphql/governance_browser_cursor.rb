# frozen_string_literal: true

module Coordinator::Web::Graphql
  class GovernanceBrowserCursor
    PREFIX = "project-governance:v1"

    def self.encode(kind, filters:, cursor:)
      Base64.urlsafe_encode64(
        JSON.generate("prefix" => PREFIX, "kind" => kind, "filters" => filters, "cursor" => cursor),
        padding: false
      )
    end

    def self.decode(value, kind, filters:)
      return unless value

      payload = JSON.parse(Base64.urlsafe_decode64(value))
      valid = payload.is_a?(Hash) && payload.keys.sort == %w[cursor filters kind prefix] &&
        payload.fetch("prefix", nil) == PREFIX && payload.fetch("kind", nil) == kind &&
        payload.fetch("filters", nil) == filters && valid_cursor?(kind, payload.fetch("cursor", nil))
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid or belongs to another query" unless valid

      payload.fetch("cursor")
    rescue ArgumentError, JSON::ParserError, TypeError
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
  end
end
