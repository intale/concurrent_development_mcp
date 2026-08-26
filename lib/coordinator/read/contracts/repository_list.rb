# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class RepositoryList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:scope).filled(:string)
        optional(:after_repository_id).maybe(:string)
        optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
      end

      rule(:scope) do
        key.failure("must be valid UTF-8") unless value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key.failure("must be at most 500 bytes") if value.bytesize > 500
        key.failure("must not have leading or trailing whitespace") unless value == value.strip
        key.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end

      rule(:after_repository_id) do
        next unless value

        key.failure("must be a Repository UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end
    end
  end
end
