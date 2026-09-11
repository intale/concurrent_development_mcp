# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class KnowledgeBrowser
    class Skills < Dry::Validation::Contract
      config.validate_keys = true

      params do
        optional(:project_ref).maybe(:string)
        optional(:scope).maybe(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:name).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:after_skill_id).maybe(:string)
      end

      rule(:name) do
        next unless value

        key.failure("is too long") if value.bytesize > Coordinator::Shared::Types::SKILL_NAME_MAXIMUM_BYTES
      end

      rule(:project_ref, :scope) do
        base.failure("project_ref and scope are mutually exclusive") if values[:project_ref] && values[:scope]
        next unless values[:scope]

        result = Coordinator::Read::Contracts::RepositoryList.new.call(scope: values[:scope])
        key(:scope).failure("must be an exact valid Project scope") if result.failure?
      end

      rule(:after_skill_id) do
        next unless value

        key.failure("must be a Skill ID") unless Coordinator::Shared::Types::SKILL_ID_PATTERN.match?(value)
      end


      rule(:after_updated_at, :after_skill_id) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_updated_at].nil? == values[:after_skill_id].nil?
        next unless values[:after_updated_at]

        unless Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
          key(:after_updated_at).failure("must be an event timestamp")
        end
      end
    end

    class SkillById < Dry::Validation::Contract
      params { required(:skill_id).filled(:string) }

      rule(:skill_id) do
        key.failure("must be a Skill ID") unless Coordinator::Shared::Types::SKILL_ID_PATTERN.match?(value)
      end
    end

    class SkillAssetById < Dry::Validation::Contract
      params do
        required(:skill_id).filled(:string)
        required(:path).filled(:string)
      end

      rule(:skill_id) do
        key.failure("must be a Skill ID") unless Coordinator::Shared::Types::SKILL_ID_PATTERN.match?(value)
      end
    end

    class Artifacts < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:kind).maybe(:string)
        optional(:labels).array(:string)
        optional(:source_kind).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:after_observation_id).maybe(:string)
      end

      rule(:kind) do
        next unless value

        key.failure("is unsupported") unless Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_KINDS.include?(value)
      end

      rule(:source_kind) do
        next unless value

        key.failure("is unsupported") unless
          Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS.include?(value)
      end

      rule(:labels) do
        next unless value

        maximum = Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT
        key.failure("contains too many labels") if value.length > maximum
        key.failure("must contain unique labels") unless value.uniq.length == value.length
        value.each_with_index do |label, index|
          label_key = key([ :labels, index ])
          label_key.failure("must be valid UTF-8") unless label.encoding == Encoding::UTF_8 && label.valid_encoding?
          label_key.failure("is too long") if
            label.bytesize > Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
          label_key.failure("must not have leading or trailing whitespace") unless label == label.strip
          label_key.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(label)
        end
      end


      rule(:after_updated_at, :after_observation_id) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_updated_at].nil? == values[:after_observation_id].nil?
        if values[:after_updated_at] &&
            !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
          key(:after_updated_at).failure("must be an event timestamp")
        end
        if values[:after_observation_id] &&
            !Coordinator::Shared::Types::UUID_V7_PATTERN.match?(values[:after_observation_id])
          key(:after_observation_id).failure("must be an Observation UUIDv7")
        end
      end
    end

    class Skill < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:name).filled(:string)
      end

      rule(:name) do
        key.failure("is too long") if value.bytesize > Coordinator::Shared::Types::SKILL_NAME_MAXIMUM_BYTES
      end
    end

    class SkillAsset < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:name).filled(:string)
        required(:path).filled(:string)
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
        required(:project_ref).filled(:string)
        required(:artifact_id).filled(:string)
      end

      rule(:artifact_id) do
        key.failure("must be an Artifact ID") unless
          Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(value)
      end
    end

    class Relationships < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
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
        key.failure("has an observation window preceding its lower bound") if through && through < after
        key.failure("requires a fixed observation window for declaration coordinates") if position && through.nil?
      end
    end
  end
end
