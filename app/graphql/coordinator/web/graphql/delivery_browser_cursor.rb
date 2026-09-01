# frozen_string_literal: true

module Coordinator::Web::Graphql
  class DeliveryBrowserCursor
    SCHEMA = "delivery-browser-cursor/v2"
    TIMELINE_KINDS = %w[
      candidates obligations merge-snapshots release-sets operation-batches evidence authorizations
    ].freeze
    INTEGER_KINDS = %w[candidate-impacts operation-batch-items].freeze

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
      if TIMELINE_KINDS.include?(kind)
        return cursor.is_a?(Hash) && cursor.keys.sort == %w[id position] &&
          cursor.fetch("position", nil).is_a?(Integer) && cursor.fetch("position") >= 0 &&
          Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(cursor.fetch("id", ""))
      end

      INTEGER_KINDS.include?(kind) && cursor.is_a?(Integer) && cursor >= 0
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
      return if TIMELINE_KINDS.include?(kind) || INTEGER_KINDS.include?(kind)

      raise InvalidCursor, "#{kind} cursor is invalid"
    end
    private_class_method :validate_kind!
  end
end
