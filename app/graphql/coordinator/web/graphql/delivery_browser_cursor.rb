# frozen_string_literal: true

module Coordinator::Web::Graphql
  class DeliveryBrowserCursor
    PREFIX = "delivery-browser:v1"
    TIMELINE_KINDS = %w[
      candidates obligations merge-snapshots release-sets operation-batches evidence authorizations
    ].freeze

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
      if TIMELINE_KINDS.include?(kind)
        return cursor.is_a?(Hash) && cursor.keys.sort == %w[id position] &&
          cursor.fetch("position", nil).is_a?(Integer) && cursor.fetch("position") >= 0 &&
          Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(cursor.fetch("id", ""))
      end

      return cursor.is_a?(Integer) && cursor >= 0 if %w[candidate-impacts operation-batch-items].include?(kind)

      false
    end
    private_class_method :valid_cursor?
  end
end
