# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CaptureDevelopmentArtifact < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: %w[agent user])
          required(:id).filled(:string)
        end
        required(:scope).filled(:string)
        required(:title).filled(:string)
        required(:kind).filled(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_KINDS)
        required(:labels).array(:string)
        required(:content).hash do
          required(:encoding).filled(:string, included_in?: %w[utf-8 binary])
          required(:media_type).filled(:string)
          optional(:text).value(:string)
          optional(:base64).value(:string)
        end
        required(:source).hash do
          required(:kind).filled(:string, included_in?: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS)
          required(:locator).filled(:string)
          required(:revision).maybe(:string)
          required(:observed_at).filled(:string)
          required(:collector).filled(:string)
        end
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:scope) do
        validate_text(key, value, minimum_bytes: 1, maximum_bytes: Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES)
      end

      rule(:title) do
        validate_text(key, value, minimum_bytes: 1, maximum_bytes: Types::DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES)
      end

      rule(:labels) do
        if value.length > Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT
          key.failure("must contain at most #{Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT} labels")
        end
        value.each_with_index do |label, index|
          validate_text(
            key([ :labels, index ]),
            label,
            minimum_bytes: 1,
            maximum_bytes: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
          )
        end
      end

      rule(:content) do
        media_type = value.fetch(:media_type)
        unless media_type.ascii_only? && Types::SKILL_MEDIA_TYPE_PATTERN.match?(media_type)
          key([ :content, :media_type ]).failure("must be a visible ASCII media type")
        end

        if value.fetch(:encoding) == "utf-8"
          text_content_failures(value).each { |path, message| key(path).failure(message) }
        else
          binary_content_failures(value).each { |path, message| key(path).failure(message) }
        end
      end

      rule(:source) do
        validate_text(
          key([ :source, :locator ]),
          value.fetch(:locator),
          minimum_bytes: 1,
          maximum_bytes: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES
        )
        revision = value.fetch(:revision)
        if revision
          validate_text(
            key([ :source, :revision ]),
            revision,
            minimum_bytes: 0,
            maximum_bytes: Types::DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES
          )
        end
        validate_text(
          key([ :source, :collector ]),
          value.fetch(:collector),
          minimum_bytes: 1,
          maximum_bytes: Types::DEVELOPMENT_ARTIFACT_COLLECTOR_MAXIMUM_BYTES
        )
        unless Types::TIMESTAMP_PATTERN.match?(value.fetch(:observed_at))
          key([ :source, :observed_at ]).failure("must be a canonical microsecond UTC timestamp")
        end
      end

      rule(:kind, :content, :source) do
        next unless values[:kind] == "external_reference"

        content = values[:content]
        source = values[:source]
        locator = source[:locator]
        base.failure("external_reference source kind must be web_page") unless source[:kind] == "web_page"
        base.failure("external_reference locator must be an absolute HTTP(S) URL") unless %r{\Ahttps?://[^\s]+\z}.match?(locator)
        base.failure("external_reference content must use utf-8") unless content[:encoding] == "utf-8"
        base.failure("external_reference media type must be text/uri-list") unless content[:media_type] == "text/uri-list"
        base.failure("external_reference text must be the exact URL followed by one newline") unless content[:text] == "#{locator}\n"
      end

      private

      def text_content_failures(content)
        failures = []
        failures << [ [ :content, :text ], "is required for utf-8 content" ] unless content.key?(:text)
        failures << [ [ :content, :base64 ], "is not allowed for utf-8 content" ] if content.key?(:base64)
        return failures unless content.key?(:text)

        text = content.fetch(:text)
        valid = text.encoding == Encoding::UTF_8 && text.valid_encoding?
        failures << [ [ :content, :text ], "must be valid UTF-8" ] unless valid
        if text.bytesize > Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES
          failures << [
            [ :content, :text ],
            "decoded content exceeds #{Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES} bytes"
          ]
        end
        failures
      end

      def binary_content_failures(content)
        failures = []
        failures << [ [ :content, :base64 ], "is required for binary content" ] unless content.key?(:base64)
        failures << [ [ :content, :text ], "is not allowed for binary content" ] if content.key?(:text)
        return failures unless content.key?(:base64)

        encoded = content.fetch(:base64)
        bytes = decode_base64(encoded)
        unless bytes
          failures << [ [ :content, :base64 ], "must be canonical unwrapped Base64" ]
          return failures
        end
        if bytes.bytesize > Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES
          failures << [
            [ :content, :base64 ],
            "decoded content exceeds #{Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES} bytes"
          ]
        end
        failures
      end

      def validate_text(key_object, value, minimum_bytes:, maximum_bytes:)
        valid_utf8 = value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be valid UTF-8") unless valid_utf8
        unless value.bytesize.between?(minimum_bytes, maximum_bytes)
          key_object.failure("must be #{minimum_bytes}..#{maximum_bytes} bytes")
        end
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end

      def decode_base64(value)
        bytes = value.unpack1("m0")
        bytes if [ bytes ].pack("m0") == value
      rescue ArgumentError
        nil
      end
    end
  end
end
