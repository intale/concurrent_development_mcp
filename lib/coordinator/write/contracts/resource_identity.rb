# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ResourceIdentity < Dry::Validation::Contract
      MAXIMUM_PATH_BYTES = 1_024
      MAXIMUM_PATH_COMPONENTS = 32

      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:kind).filled(:string, included_in?: %w[file directory])
        required(:path).filled(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7 Repository ID") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:path) do
        unless value.encoding == Encoding::UTF_8 && value.valid_encoding?
          key.failure("must be valid UTF-8")
          next
        end

        key.failure("must be at most #{MAXIMUM_PATH_BYTES} bytes") if value.bytesize > MAXIMUM_PATH_BYTES
        key.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
        key.failure("must use '/' separators") if value.include?("\\")
        key.failure("must be relative") if value.start_with?("/") || /\A[A-Za-z]:\//.match?(value)
        key.failure("must not end with '/'") if value.end_with?("/")

        components = value.split("/", -1)
        key.failure("must not contain empty components") if components.any?(&:empty?)
        key.failure("must not contain '.' components") if components.include?(".")
        key.failure("must not contain '..' components") if components.include?("..")
        if components.length > MAXIMUM_PATH_COMPONENTS
          key.failure("must contain at most #{MAXIMUM_PATH_COMPONENTS} components")
        end
      end
    end
  end
end
