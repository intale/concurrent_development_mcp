# frozen_string_literal: true

module Coordinator::Web::Graphql
  class ProjectCursor
    PREFIX = "project-catalog:v1"

    def self.encode(repository_id)
      Base64.urlsafe_encode64("#{PREFIX}:#{repository_id}", padding: false)
    end

    def self.decode(cursor)
      return unless cursor

      prefix, repository_id = Base64.urlsafe_decode64(cursor).split(":", 3).then do |parts|
        [ parts.first(2).join(":"), parts.fetch(2, nil) ]
      end
      unless prefix == PREFIX && Coordinator::Shared::Types::UUID_V7_PATTERN.match?(repository_id.to_s)
        raise InvalidCursor, "project cursor is invalid"
      end

      repository_id
    rescue ArgumentError
      raise InvalidCursor, "project cursor is invalid"
    end
  end
end
