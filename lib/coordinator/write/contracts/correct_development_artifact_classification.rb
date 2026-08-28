# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CorrectDevelopmentArtifactClassification < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: %w[agent user])
          required(:id).filled(:string)
        end
        required(:observation_id).filled(:string)
        required(:expected_revision).filled(:integer)
        required(:title).filled(:string)
        required(:kind).filled(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_KINDS)
        required(:labels).array(:string)
        required(:reason).filled(:string)
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::PUBLIC_COMMAND_ID_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:observation_id) do
        unless Types::DEVELOPMENT_ARTIFACT_OBSERVATION_ID_PATTERN.match?(value)
          key.failure("must be a valid Artifact observation ID")
        end
      end

      rule(:expected_revision) do
        maximum = Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS
        key.failure("must be between 1 and #{maximum}") unless (1..maximum).cover?(value)
      end

      rule(:title) do
        validate_text(key, value, maximum_bytes: Types::DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES)
      end

      rule(:labels) do
        if value.length > Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT
          key.failure("must contain at most #{Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT} labels")
        end
        key.failure("must not contain duplicate labels") unless value.uniq.length == value.length
        value.each_with_index do |label, index|
          validate_text(
            key([ :labels, index ]),
            label,
            maximum_bytes: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
          )
        end
      end

      rule(:reason) do
        validate_text(key, value, maximum_bytes: 1_000)
      end

      private

      def validate_text(key_object, value, maximum_bytes:)
        valid_utf8 = value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be valid UTF-8") unless valid_utf8
        key_object.failure("must be 1..#{maximum_bytes} bytes") unless value.bytesize.between?(1, maximum_bytes)
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end
    end
  end
end
