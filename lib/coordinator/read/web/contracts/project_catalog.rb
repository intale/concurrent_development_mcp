# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class ProjectCatalog
    class Discovery < Dry::Validation::Contract
      config.validate_keys = true

      params do
        optional(:search).maybe(:string, min_size?: 1)
        optional(:sort).filled(:string, included_in?: %w[oldest_first newest_first])
        optional(:after_scope).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:repositories_first).filled(:integer, gteq?: 1, lteq?: 20)
      end

      rule(:search) do
        next unless value

        key.failure("must be valid UTF-8") unless value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key.failure("must be at most 200 bytes") if value.bytesize > 200
        key.failure("must not have leading or trailing whitespace") unless value == value.strip
        key.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end

      rule(:after_scope) do
        next unless value

        result = Coordinator::Read::Contracts::RepositoryList.new.call(scope: value)
        key.failure("must be an exact valid Project scope") if result.failure?
      end

      rule(:after_scope, :after_updated_at) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_scope].nil? == values[:after_updated_at].nil?
        next unless values[:after_updated_at]

        key(:after_updated_at).failure("must be an event timestamp") unless
          Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end
    end

    class Overview < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string, max_size?: 2_048)
        optional(:after_repository_id).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:repositories_first).filled(:integer, gteq?: 1, lteq?: 100)
      end

      rule(:after_repository_id) do
        next unless value

        key.failure("must be a Repository UUIDv7") unless
          Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:after_repository_id, :after_updated_at) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_repository_id].nil? == values[:after_updated_at].nil?
      end
    end
  end
end
