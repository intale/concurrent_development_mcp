# frozen_string_literal: true

module Coordinator::Web::Graphql
  class ProjectCursor
    PREFIX = "project-catalog:v2"

    class ProjectsPayloadContract < Dry::Validation::Contract
      config.validate_keys = true

      json do
        required(:prefix).filled(:string, eql?: PREFIX)
        required(:kind).filled(:string, eql?: "projects")
        required(:after_scope).filled(:string)
        required(:search).maybe(:string)
        required(:sort).filled(:string, included_in?: %w[scope_asc scope_desc])
      end
    end

    class RepositoriesPayloadContract < Dry::Validation::Contract
      config.validate_keys = true

      json do
        required(:prefix).filled(:string, eql?: PREFIX)
        required(:kind).filled(:string, eql?: "repositories")
        required(:project_ref).filled(:string)
        required(:after_repository_id).filled(:string)
      end
    end

    def self.encode_projects(after_scope:, search:, sort:)
      encode(
        "prefix" => PREFIX,
        "kind" => "projects",
        "after_scope" => after_scope,
        "search" => search,
        "sort" => sort
      )
    end

    def self.decode_projects(cursor, search:, sort:)
      return unless cursor

      payload = decode(cursor, ProjectsPayloadContract.new, "project")
      canonical = encode_projects(
        after_scope: payload.fetch(:after_scope),
        search: payload[:search],
        sort: payload.fetch(:sort)
      )
      valid_scope = Coordinator::Read::Contracts::RepositoryList.new.call(
        scope: payload.fetch(:after_scope)
      ).success?
      raise InvalidCursor, "project cursor is invalid" unless canonical == cursor && valid_scope
      unless payload.values_at(:search, :sort) == [ search, sort ]
        raise InvalidCursor, "project cursor does not match this query"
      end

      payload.fetch(:after_scope)
    end

    def self.encode_repositories(project_ref:, after_repository_id:)
      encode(
        "prefix" => PREFIX,
        "kind" => "repositories",
        "project_ref" => project_ref,
        "after_repository_id" => after_repository_id
      )
    end

    def self.decode_repositories(cursor, project_ref:)
      return unless cursor

      payload = decode(cursor, RepositoriesPayloadContract.new, "project repository")
      canonical = encode_repositories(
        project_ref: payload.fetch(:project_ref),
        after_repository_id: payload.fetch(:after_repository_id)
      )
      valid = canonical == cursor &&
        Coordinator::Shared::Types::UUID_V7_PATTERN.match?(payload.fetch(:after_repository_id))
      begin
        Coordinator::Read::Web::ProjectReference.new.decode(payload.fetch(:project_ref))
      rescue Coordinator::Read::Web::ProjectReference::InvalidReference
        valid = false
      end
      raise InvalidCursor, "project repository cursor is invalid" unless valid
      unless payload.fetch(:project_ref) == project_ref
        raise InvalidCursor, "project repository cursor does not match this project"
      end

      payload.fetch(:after_repository_id)
    end

    def self.encode(payload)
      document = Coordinator::Shared::CanonicalJson.new.encode(payload)
      Base64.urlsafe_encode64(document, padding: false)
    end
    private_class_method :encode

    def self.decode(cursor, contract, label)
      document = JSON.parse(Base64.urlsafe_decode64(cursor))
      payload = contract.call(document)
      raise InvalidCursor, "#{label} cursor is invalid" if payload.failure?

      payload.to_h
    rescue ArgumentError, JSON::ParserError, TypeError, Coordinator::Shared::CanonicalJson::Error
      raise InvalidCursor, "#{label} cursor is invalid"
    end
    private_class_method :decode
  end
end
