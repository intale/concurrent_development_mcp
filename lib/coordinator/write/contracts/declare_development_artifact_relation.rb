# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DeclareDevelopmentArtifactRelation < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: %w[agent user])
          required(:id).filled(:string)
        end
        required(:source_artifact_id).filled(:string)
        required(:relation).filled(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS)
        required(:target).hash do
          required(:kind).filled(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS)
          required(:id).filled(:string)
        end
        required(:attributes).hash do
          optional(:path).filled(:string)
        end
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:source_artifact_id) do
        key.failure("must be a valid Artifact ID") unless Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(value)
      end

      rule(:target) do
        target_id = value.fetch(:id)
        valid_utf8 = target_id.encoding == Encoding::UTF_8 && target_id.valid_encoding?
        key([ :target, :id ]).failure("must be valid UTF-8") unless valid_utf8
        unless target_id.bytesize.between?(1, Types::DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES)
          key([ :target, :id ]).failure("has an invalid byte length")
        end
        key([ :target, :id ]).failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(target_id)
        if value.fetch(:kind) == "artifact" && !Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(target_id)
          key([ :target, :id ]).failure("must be a valid Artifact ID")
        end
      end

      rule(:relation, :attributes) do
        path = values[:attributes][:path]
        if values[:relation] != "documents" && path
          key(:attributes).failure("must be empty unless relation is documents")
          next
        end
        next unless path

        valid_utf8 = path.encoding == Encoding::UTF_8 && path.valid_encoding?
        key([ :attributes, :path ]).failure("must be valid UTF-8") unless valid_utf8
        unless path.bytesize.between?(1, Types::DEVELOPMENT_ARTIFACT_RELATION_PATH_MAXIMUM_BYTES)
          key([ :attributes, :path ]).failure("has an invalid byte length")
        end
        invalid = path.start_with?("/") || path.include?("\\") ||
                  path.split("/", -1).any? { _1.empty? || _1 == "." || _1 == ".." }
        key([ :attributes, :path ]).failure("must be a safe relative POSIX path") if invalid
      end

      rule(:source_artifact_id, :target) do
        target = values[:target]
        next unless target[:kind] == "artifact" && target[:id] == values[:source_artifact_id]

        base.failure("an Artifact cannot relate to itself")
      end
    end
  end
end
