# frozen_string_literal: true

module Coordinator::Write
  module Content
    class InputContract < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:encoding).filled(:string, included_in?: %w[utf-8 binary])
        required(:media_type).filled(:string)
        optional(:text).value(:string)
        optional(:base64).value(:string)
      end

      rule(:media_type) do
        unless value.ascii_only? && Types::SKILL_MEDIA_TYPE_PATTERN.match?(value)
          key.failure("must be a visible ASCII media type")
        end
      end

      rule do
        next unless values[:encoding]

        failures = values[:encoding] == "utf-8" ? text_failures(values) : binary_failures(values)
        failures.each { base.failure(_1) }
      end

      private

      def text_failures(values)
        failures = []
        failures << "text is required for utf-8 content" unless values.key?(:text)
        failures << "base64 is not allowed for utf-8 content" if values.key?(:base64)
        return failures unless values.key?(:text)

        text = values.fetch(:text)
        valid = text.encoding == Encoding::UTF_8 && text.valid_encoding?
        failures << "text must be valid UTF-8" unless valid
        if text.bytesize > Types::CONTENT_MAXIMUM_BYTES
          failures << "text exceeds #{Types::CONTENT_MAXIMUM_BYTES} bytes"
        end
        failures
      end

      def binary_failures(values)
        failures = []
        failures << "base64 is required for binary content" unless values.key?(:base64)
        failures << "text is not allowed for binary content" if values.key?(:text)
        return failures unless values.key?(:base64)

        bytes = canonical_base64_bytes(values.fetch(:base64))
        unless bytes
          failures << "base64 must be canonical and unwrapped"
          return failures
        end
        if bytes.bytesize > Types::CONTENT_MAXIMUM_BYTES
          failures << "binary content exceeds #{Types::CONTENT_MAXIMUM_BYTES} bytes"
        end
        failures
      end

      def canonical_base64_bytes(value)
        bytes = value.unpack1("m0")
        bytes if [ bytes ].pack("m0") == value
      rescue ArgumentError
        nil
      end
    end
  end
end
