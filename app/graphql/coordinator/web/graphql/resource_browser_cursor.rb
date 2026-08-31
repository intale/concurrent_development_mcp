# frozen_string_literal: true

module Coordinator::Web::Graphql
  class ResourceBrowserCursor
    PREFIX = "project-resources:v1"

    def self.encode_resources(repository_id:, after_id:, resource_kind:, lifecycle_status:)
      encode(
        "kind" => "resources",
        "repository_id" => repository_id,
        "after_id" => after_id,
        "resource_kind" => resource_kind,
        "lifecycle_status" => lifecycle_status
      )
    end

    def self.decode_resources(cursor, repository_id:, resource_kind:, lifecycle_status:)
      return unless cursor

      payload = decode(cursor, "resources")
      valid = payload.values_at("repository_id", "resource_kind", "lifecycle_status") ==
        [ repository_id, resource_kind, lifecycle_status ]
      raise InvalidCursor, "resource cursor does not match this query" unless valid

      payload.fetch("after_id")
    end

    def self.encode_active_leases(repository_id:, after_id:, as_of:)
      encode(
        "kind" => "active-leases",
        "repository_id" => repository_id,
        "after_id" => after_id,
        "as_of" => as_of
      )
    end

    def self.decode_active_leases(cursor, repository_id:)
      return unless cursor

      payload = decode(cursor, "active-leases")
      unless payload.fetch("repository_id") == repository_id
        raise InvalidCursor, "active lease cursor does not match this project"
      end

      { after_id: payload.fetch("after_id"), as_of: payload.fetch("as_of") }
    end

    def self.encode(payload)
      Base64.urlsafe_encode64(JSON.generate(payload.merge("prefix" => PREFIX)), padding: false)
    end
    private_class_method :encode

    def self.decode(cursor, kind)
      payload = JSON.parse(Base64.urlsafe_decode64(cursor))
      valid = payload.is_a?(Hash) && payload.fetch("prefix", nil) == PREFIX &&
        payload.fetch("kind", nil) == kind &&
        Coordinator::Shared::Types::UUID_V7_PATTERN.match?(payload.fetch("repository_id", "")) &&
        Coordinator::Shared::Types::UUID_V7_PATTERN.match?(payload.fetch("after_id", ""))
      valid &&= Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(payload.fetch("as_of", "")) if
        kind == "active-leases"
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid" unless valid

      payload
    rescue ArgumentError, JSON::ParserError, TypeError
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid"
    end
    private_class_method :decode
  end
end
