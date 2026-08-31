# frozen_string_literal: true

module Coordinator::Web::Graphql
  class KnowledgeBrowserCursor
    PREFIX = "project-knowledge:v1"

    def self.encode_skills(repository_id:, after_id:, skill_name:)
      encode(
        "kind" => "skills",
        "repository_id" => repository_id,
        "after_id" => after_id,
        "skill_name" => skill_name
      )
    end

    def self.decode_skills(cursor, repository_id:, skill_name:)
      return unless cursor

      payload = decode(cursor, "skills")
      valid = payload.values_at("repository_id", "skill_name") == [ repository_id, skill_name ]
      raise InvalidCursor, "skill cursor does not match this query" unless valid

      payload.fetch("after_id")
    end

    def self.encode_artifacts(repository_id:, after_position:, artifact_kind:, labels:, source_kind:)
      encode(
        "kind" => "artifacts",
        "repository_id" => repository_id,
        "after_position" => after_position,
        "artifact_kind" => artifact_kind,
        "labels" => labels,
        "source_kind" => source_kind
      )
    end

    def self.decode_artifacts(cursor, repository_id:, artifact_kind:, labels:, source_kind:)
      return unless cursor

      payload = decode(cursor, "artifacts")
      valid = payload.values_at("repository_id", "artifact_kind", "labels", "source_kind") ==
        [ repository_id, artifact_kind, labels, source_kind ]
      raise InvalidCursor, "artifact cursor does not match this query" unless valid

      payload.fetch("after_position")
    end

    def self.encode_relations(repository_id:, artifact_id:, direction:, relation:, cursor:)
      encode(
        "kind" => "relations",
        "repository_id" => repository_id,
        "artifact_id" => artifact_id,
        "direction" => direction,
        "relation" => relation,
        "cursor" => cursor.to_h
      )
    end

    def self.decode_relations(cursor, repository_id:, artifact_id:, direction:, relation:)
      return unless cursor

      payload = decode(cursor, "relations")
      valid = payload.values_at("repository_id", "artifact_id", "direction", "relation") ==
        [ repository_id, artifact_id, direction, relation ]
      raise InvalidCursor, "artifact relation cursor does not match this query" unless valid

      payload.fetch("cursor").transform_keys(&:to_sym)
    end

    def self.encode(payload)
      Base64.urlsafe_encode64(JSON.generate(payload.merge("prefix" => PREFIX)), padding: false)
    end
    private_class_method :encode

    def self.decode(cursor, kind)
      payload = JSON.parse(Base64.urlsafe_decode64(cursor))
      valid = payload.is_a?(Hash) && payload.fetch("prefix", nil) == PREFIX &&
        payload.fetch("kind", nil) == kind &&
        Coordinator::Shared::Types::UUID_V7_PATTERN.match?(payload.fetch("repository_id", ""))
      valid &&= valid_kind_payload?(payload, kind)
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid" unless valid

      payload
    rescue ArgumentError, JSON::ParserError, TypeError
      raise InvalidCursor, "#{kind.tr('-', ' ')} cursor is invalid"
    end
    private_class_method :decode

    def self.valid_kind_payload?(payload, kind)
      case kind
      when "skills"
        Coordinator::Shared::Types::SKILL_ID_PATTERN.match?(payload.fetch("after_id", ""))
      when "artifacts"
        payload.fetch("after_position", nil).is_a?(Integer) && payload.fetch("after_position") >= 0 &&
          payload.fetch("labels", nil).is_a?(Array)
      when "relations"
        valid_relation_payload?(payload)
      else
        false
      end
    end
    private_class_method :valid_kind_payload?

    def self.valid_relation_payload?(payload)
      cursor = payload.fetch("cursor", nil)
      Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(payload.fetch("artifact_id", "")) &&
        cursor.is_a?(Hash) && cursor.fetch("after_observed_sequence", nil).is_a?(Integer) &&
        cursor.keys.sort == %w[
          after_declared_global_position
          after_observed_sequence
          after_relation_id
          through_observed_sequence
        ]
    end
    private_class_method :valid_relation_payload?
  end
end
