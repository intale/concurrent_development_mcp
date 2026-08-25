# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DevelopmentArtifactList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        optional(:scope).maybe(:string)
        optional(:kind).maybe(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_KINDS)
        optional(:labels).array(:string)
        optional(:source_kind).maybe(
          :string,
          included_in?: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS
        )
        optional(:relation_target).maybe(:hash) do
          required(:kind).filled(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS)
          required(:id).filled(:string)
        end
        optional(:after_global_position).maybe(:integer, gteq?: 0)
        optional(:limit).maybe(
          :integer,
          gteq?: 1,
          lteq?: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
        )
      end

      rule(:scope) do
        validate_text(key, value, Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES) if value
      end

      rule(:labels) do
        next unless value

        if value.length > Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT
          key.failure("must contain at most #{Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT} labels")
        end
        key.failure("must contain unique labels") unless value.uniq.length == value.length
        value.each_with_index do |label, index|
          validate_text(key([ :labels, index ]), label, Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES)
        end
      end

      rule(:relation_target) do
        next unless value

        target_id = value.fetch(:id)
        validate_text(key([ :relation_target, :id ]), target_id, Types::DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES)
        if value.fetch(:kind) == "artifact" && !Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(target_id)
          key([ :relation_target, :id ]).failure("must be a valid Artifact ID")
        end
      end

      private

      def validate_text(key_object, value, maximum_bytes)
        valid_utf8 = value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be valid UTF-8") unless valid_utf8
        key_object.failure("must be 1..#{maximum_bytes} bytes") unless value.bytesize.between?(1, maximum_bytes)
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end
    end
  end
end
