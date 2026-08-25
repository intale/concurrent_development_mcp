# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class SkillGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:name).filled(:string)
        required(:scope).filled(:string)
      end

      rule(:name) do
        validate_identity(key, value, maximum_bytes: Types::SKILL_NAME_MAXIMUM_BYTES)
      end

      rule(:scope) do
        validate_identity(key, value, maximum_bytes: Types::SKILL_SCOPE_MAXIMUM_BYTES)
      end

      private

      def validate_identity(key_object, value, maximum_bytes:)
        key_object.failure("must be valid UTF-8") unless value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be at most #{maximum_bytes} bytes") if value.bytesize > maximum_bytes
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end
    end
  end
end
