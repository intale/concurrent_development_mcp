# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class KnowledgeBrowser
    class Catalog < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:skill_name).maybe(:string)
        optional(:after_skill_id).maybe(:string)
        optional(:artifact_kind).maybe(:string)
        optional(:artifact_labels).array(:string)
        optional(:artifact_source_kind).maybe(:string)
        optional(:after_artifact_global_position).maybe(:integer, gteq?: 0)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:skill_name) do
        next unless value

        key.failure("is too long") if value.bytesize > Coordinator::Shared::Types::SKILL_NAME_MAXIMUM_BYTES
      end

      rule(:after_skill_id) do
        next unless value

        key.failure("must be a Skill ID") unless Coordinator::Shared::Types::SKILL_ID_PATTERN.match?(value)
      end

      rule(:artifact_kind) do
        next unless value

        key.failure("is unsupported") unless Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_KINDS.include?(value)
      end

      rule(:artifact_source_kind) do
        next unless value

        key.failure("is unsupported") unless Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS.include?(value)
      end

      rule(:artifact_labels) do
        next unless value

        maximum = Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT
        key.failure("contains too many labels") if value.length > maximum
        key.failure("must contain unique labels") unless value.uniq.length == value.length
        value.each_with_index do |label, index|
          label_key = key([ :artifact_labels, index ])
          label_key.failure("must be valid UTF-8") unless label.encoding == Encoding::UTF_8 && label.valid_encoding?
          label_key.failure("is too long") if
            label.bytesize > Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
          label_key.failure("must not have leading or trailing whitespace") unless label == label.strip
          label_key.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(label)
        end
      end
    end

    class Skill < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:name).filled(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:name) do
        key.failure("is too long") if value.bytesize > Coordinator::Shared::Types::SKILL_NAME_MAXIMUM_BYTES
      end
    end

    class SkillAsset < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:name).filled(:string)
        required(:path).filled(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:name) do
        key.failure("is too long") if value.bytesize > Coordinator::Shared::Types::SKILL_NAME_MAXIMUM_BYTES
      end

      rule(:path) do
        key.failure("is too long") if value.bytesize > Coordinator::Shared::Types::SKILL_ASSET_PATH_MAXIMUM_BYTES
      end
    end

    class Artifact < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:artifact_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:direction).filled(:string)
        optional(:relation).maybe(:string)
        optional(:cursor).maybe(:hash) do
          required(:after_observed_sequence).filled(:integer, gteq?: 0)
          required(:through_observed_sequence).maybe(:integer, gteq?: 0)
          required(:after_declared_global_position).maybe(:integer, gteq?: 0)
          required(:after_relation_id).maybe(:string)
        end
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:artifact_id) do
        key.failure("must be an Artifact ID") unless
          Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(value)
      end

      rule(:direction) do
        key.failure("is unsupported") if value && !%w[incoming outgoing both].include?(value)
      end

      rule(:relation) do
        next unless value

        key.failure("is unsupported") unless
          Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS.include?(value)
      end

      rule(:cursor) do
        next unless value

        position = value[:after_declared_global_position]
        relation_id = value[:after_relation_id]
        key.failure("has incomplete declaration coordinates") unless position.nil? == relation_id.nil?
        if relation_id && !Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_ID_PATTERN.match?(relation_id)
          key.failure("contains an invalid relation ID")
        end
        after = value.fetch(:after_observed_sequence)
        through = value[:through_observed_sequence]
        if through && through < after
          key.failure("has an observation window preceding its lower bound")
        end
        key.failure("requires a fixed observation window for declaration coordinates") if position && through.nil?
      end
    end
  end
end
