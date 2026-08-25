# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class SkillList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        optional(:name).maybe(:string)
        optional(:scope).maybe(:string)
        optional(:after_skill_id).maybe(:string)
        optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
      end

      rule(:name) do
        validate_identity(key, value, maximum_bytes: Types::SKILL_NAME_MAXIMUM_BYTES) if value
      end

      rule(:scope) do
        validate_identity(key, value, maximum_bytes: Types::SKILL_SCOPE_MAXIMUM_BYTES) if value
      end

      rule(:after_skill_id) do
        next unless value

        key.failure("must be a valid Skill ID") unless Types::SKILL_ID_PATTERN.match?(value)
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
