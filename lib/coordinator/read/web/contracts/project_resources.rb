# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class ProjectResources < Dry::Validation::Contract
    config.validate_keys = true

    params do
      required(:repository_id).filled(:string)
      required(:lease_as_of).filled(:string)
      optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
      optional(:resource_after_id).maybe(:string)
      optional(:lease_after_id).maybe(:string)
      optional(:resource_kind).maybe(:string)
      optional(:resource_lifecycle_status).maybe(:string)
    end

    rule(:repository_id, :resource_after_id, :lease_after_id) do
      values.values_at(:repository_id, :resource_after_id, :lease_after_id).compact.each do |identifier|
        key.failure("contains an identifier that is not UUIDv7") unless
          Coordinator::Shared::Types::UUID_V7_PATTERN.match?(identifier)
      end
    end

    rule(:lease_as_of) do
      key.failure("must be a canonical UTC timestamp") unless
        Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(value)
    end

    rule(:resource_kind) do
      key.failure("must be file or directory") if value && !%w[file directory].include?(value)
    end

    rule(:resource_lifecycle_status) do
      key.failure("must be registered, current, or inactive") if
        value && !%w[registered current inactive].include?(value)
    end
  end
end
