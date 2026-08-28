# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DevelopmentArtifactLocatorResolve < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:scope).filled(:string)
        required(:source_kind).filled(
          :string,
          included_in?: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS
        )
        required(:locator).filled(:string)
        optional(:source_revision).maybe(:string)
        optional(:cursor).maybe(:hash) do
          required(:after_observed_sequence).filled(:integer, gteq?: 0)
          required(:through_observed_sequence).maybe(:integer, gteq?: 0)
          required(:after_current_global_position).maybe(:integer, gteq?: 0)
          required(:after_observation_id).maybe(:string)
        end
        optional(:limit).maybe(
          :integer,
          gteq?: 1,
          lteq?: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
        )
      end

      rule(:scope) do
        validate_text(key, value, 1, Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES)
      end

      rule(:locator) do
        validate_text(key, value, 1, Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES)
      end

      rule(:source_revision) do
        next unless value

        validate_text(key, value, 0, Types::DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES)
      end

      rule(:cursor) do
        next unless value

        after_position = value[:after_current_global_position]
        after_observation_id = value[:after_observation_id]
        unless after_position.nil? == after_observation_id.nil?
          key.failure("current position and observation ID must both be present or absent")
        end
        if after_observation_id &&
           !Types::DEVELOPMENT_ARTIFACT_OBSERVATION_ID_PATTERN.match?(after_observation_id)
          key([ :cursor, :after_observation_id ]).failure("must be a valid Artifact observation ID")
        end
        through = value[:through_observed_sequence]
        if through && through < value.fetch(:after_observed_sequence)
          key([ :cursor, :through_observed_sequence ]).failure(
            "must not precede the observed lower bound"
          )
        end
        if after_position && through.nil?
          key.failure("a current position requires a fixed observation window")
        end
      end

      private

      def validate_text(key_object, value, minimum_bytes, maximum_bytes)
        valid_utf8 = value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be valid UTF-8") unless valid_utf8
        unless value.bytesize.between?(minimum_bytes, maximum_bytes)
          key_object.failure("must be #{minimum_bytes}..#{maximum_bytes} bytes")
        end
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end
    end
  end
end
