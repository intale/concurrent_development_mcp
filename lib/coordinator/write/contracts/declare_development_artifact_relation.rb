# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DeclareDevelopmentArtifactRelation < Dry::Validation::Contract
      TARGET_KINDS_BY_RELATION = {
        "references" => Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS,
        "contains" => %w[artifact],
        "documents" => Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS,
        "evidences" => Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS,
        "derived_from" => Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS,
        "supersedes" => %w[artifact],
        "produced_by_import" => %w[artifact build checkpoint]
      }.freeze

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
          optional(:fragment).filled(:string)
          optional(:normalized_locator).filled(:string)
        end
        optional(:supersedes).hash do
          required(:relation_id).filled(:string)
          required(:reason).filled(:string)
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
        attributes = values[:attributes]
        path = attributes[:path]
        fragment = attributes[:fragment]
        normalized_locator = attributes[:normalized_locator]
        unless %w[references documents].include?(values[:relation]) || attributes.values.none?
          key(:attributes).failure("must be empty unless relation is references or documents")
          next
        end
        if values[:relation] == "documents" && (fragment || normalized_locator)
          key(:attributes).failure("documents may carry only path")
        end
        if (fragment || normalized_locator) && !path
          key(:attributes).failure("path is required with fragment or normalized_locator")
        end
        next unless path

        valid_utf8 = path.encoding == Encoding::UTF_8 && path.valid_encoding?
        key([ :attributes, :path ]).failure("must be valid UTF-8") unless valid_utf8
        unless path.bytesize.between?(1, Types::DEVELOPMENT_ARTIFACT_RELATION_PATH_MAXIMUM_BYTES)
          key([ :attributes, :path ]).failure("has an invalid byte length")
        end
        invalid = path.start_with?("/") || path.include?("\\") || path.include?("?") || path.include?("#") ||
                  path.split("/", -1).any?(&:empty?) || /[\u0000-\u001f\u007f]/.match?(path)
        key([ :attributes, :path ]).failure("must be a relative POSIX link path") if invalid

        if fragment && !Text.valid?(fragment, max_size: Types::DEVELOPMENT_ARTIFACT_RELATION_FRAGMENT_MAXIMUM_BYTES)
          key([ :attributes, :fragment ]).failure("must be nonblank UTF-8 text within the byte limit")
        end
        if fragment&.start_with?("#") || fragment&.match?(/[\u0000-\u001f\u007f]/)
          key([ :attributes, :fragment ]).failure("must omit # and control characters")
        end
        if normalized_locator && !Text.valid?(
          normalized_locator,
          max_size: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES
        )
          key([ :attributes, :normalized_locator ]).failure(
            "must be nonblank UTF-8 text within the byte limit"
          )
        end
      end

      rule(:relation, :target) do
        allowed = TARGET_KINDS_BY_RELATION.fetch(values[:relation])
        key([ :target, :kind ]).failure("is incompatible with relation") unless allowed.include?(values[:target][:kind])
      end

      rule(:source_artifact_id, :target) do
        target = values[:target]
        next unless target[:kind] == "artifact" && target[:id] == values[:source_artifact_id]

        base.failure("an Artifact cannot relate to itself")
      end

      rule(:supersedes) do
        next unless value

        unless Types::DEVELOPMENT_ARTIFACT_RELATION_ID_PATTERN.match?(value[:relation_id])
          key([ :supersedes, :relation_id ]).failure("must be a valid relation ID")
        end
        unless Text.valid?(
          value[:reason],
          max_size: Types::DEVELOPMENT_ARTIFACT_RELATION_SUPERSESSION_REASON_MAXIMUM_BYTES
        )
          key([ :supersedes, :reason ]).failure("must be nonblank UTF-8 text within the byte limit")
        end
      end
    end
  end
end
