# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class UpdateDevelopmentArtifact < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: %w[agent user])
          required(:id).filled(:string)
        end
        required(:artifact_id).filled(:string)
        required(:expected_revision).filled(:integer)
        required(:changes).hash do
          optional(:scope).filled(:string)
          optional(:title).filled(:string)
          optional(:kind).filled(:string)
          optional(:labels).array(:string)
          optional(:content).hash do
            required(:encoding).filled(:string, included_in?: %w[utf-8 binary])
            required(:media_type).filled(:string)
            optional(:text).value(:string)
            optional(:base64).value(:string)
          end
          optional(:source).hash do
            required(:kind).filled(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS)
            required(:locator).filled(:string)
            required(:revision).maybe(:string)
            required(:observed_at).filled(:string)
            required(:collector).filled(:string)
          end
        end
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::PUBLIC_COMMAND_ID_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:artifact_id) do
        key.failure("must be a valid Artifact UUIDv7") unless Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(value)
      end

      rule(:expected_revision) do
        key.failure("must be non-negative") unless value >= 0
      end

      rule(:changes) do
        key.failure("must contain at least one change") if value.empty?
        if value.key?(:labels)
          labels = value.fetch(:labels)
          key([ :labels ]).failure("must contain at most #{Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT} labels") if
            labels.length > Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT
          key([ :labels ]).failure("must not contain duplicate labels") unless labels.uniq.length == labels.length
          labels.each_with_index do |label, index|
            validate_text(key([ :labels, index ]), label, Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES)
          end
        end
        validate_text(key([ :scope ]), value[:scope], Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES) if value[:scope]
        validate_text(key([ :title ]), value[:title], Types::DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES) if value[:title]
        if value[:kind] && !Types::DEVELOPMENT_ARTIFACT_KINDS.include?(value[:kind])
          key([ :kind ]).failure("is not a supported Artifact kind")
        end
        validate_content(value[:content], key) if value[:content]
        validate_source(value[:source], key) if value[:source]
      end

      private

      def validate_text(key_object, value, maximum_bytes)
        valid_utf8 = value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be valid UTF-8") unless valid_utf8
        key_object.failure("must be 1..#{maximum_bytes} bytes") unless value.bytesize.between?(1, maximum_bytes)
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end

      def validate_content(content, key_object)
        media_type = content.fetch(:media_type)
        unless media_type.ascii_only? && Types::SKILL_MEDIA_TYPE_PATTERN.match?(media_type)
          key_object.failure("content media type must be a visible ASCII media type")
        end
        if content.fetch(:encoding) == "utf-8"
          key_object.failure("utf-8 content requires text") unless content.key?(:text)
          key_object.failure("utf-8 content does not allow base64") if content.key?(:base64)
          if content[:text]
            text = content.fetch(:text)
            key_object.failure("content text must be valid UTF-8") unless
              text.encoding == Encoding::UTF_8 && text.valid_encoding?
            key_object.failure("content text exceeds content limit") if
              text.bytesize > Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES
          end
        else
          key_object.failure("binary content requires base64") unless content.key?(:base64)
          key_object.failure("binary content does not allow text") if content.key?(:text)
          return unless content[:base64]

          begin
            bytes = content[:base64].unpack1("m0")
            key_object.failure("binary content must use canonical unwrapped Base64") unless
              [ bytes ].pack("m0") == content[:base64]
            key_object.failure("binary content exceeds content limit") if
              bytes.bytesize > Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES
          rescue ArgumentError
            key_object.failure("binary content must use canonical unwrapped Base64")
          end
        end
      end

      def validate_source(source, key_object)
        validate_text(key_object, source.fetch(:locator), Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES)
        validate_text(key_object, source.fetch(:collector), Types::DEVELOPMENT_ARTIFACT_COLLECTOR_MAXIMUM_BYTES)
        if source[:revision]
          validate_text(key_object, source.fetch(:revision), Types::DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES)
        end
        key_object.failure("source observed_at must be a canonical microsecond UTC timestamp") unless
          Types::TIMESTAMP_PATTERN.match?(source.fetch(:observed_at))
      end
    end
  end
end
