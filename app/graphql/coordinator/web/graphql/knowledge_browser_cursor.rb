# frozen_string_literal: true

module Coordinator::Web::Graphql
  class KnowledgeBrowserCursor
    SCHEMA = "project-knowledge-cursor/v2"
    KINDS = %w[skills artifacts relationships].freeze

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
        valid_cursor?(cursor, kind) &&
        encode(kind, filters:, cursor:) == value
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid" unless valid

      cursor
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError, NoMethodError
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid"
    end

    def self.valid_cursor?(cursor, kind)
      case kind
      when "skills"
        cursor.keys.sort == [ "after_id" ] &&
          Coordinator::Shared::Types::SKILL_ID_PATTERN.match?(cursor.fetch("after_id", ""))
      when "artifacts"
        cursor.keys.sort == [ "after_position" ] &&
          cursor.fetch("after_position", nil).is_a?(Integer) && cursor.fetch("after_position") >= 0
      when "relationships"
        valid_relationship_cursor?(cursor)
      else
        false
      end
    end
    private_class_method :valid_cursor?

    def self.valid_relationship_cursor?(cursor)
      cursor.is_a?(Hash) && cursor.keys.sort == %w[
        after_declared_global_position
        after_observed_sequence
        after_relation_id
        through_observed_sequence
      ] && cursor.fetch("after_observed_sequence", nil).is_a?(Integer)
    end
    private_class_method :valid_relationship_cursor?

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
