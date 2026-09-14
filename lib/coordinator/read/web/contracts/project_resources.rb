# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class ProjectResources
    RESOURCE_KINDS = %w[file directory].freeze
    RESOURCE_LIFECYCLES = %w[registered current inactive].freeze
    COLLECTION_KINDS = %w[resources active_work_intentions].freeze
    DETAIL_KINDS = %w[resource work_intention].freeze

    class Collection < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:kind).filled(:string)
        required(:as_of).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:after_id).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:sort).filled(:string, included_in?: %w[newest_first oldest_first])
        optional(:path).maybe(:string, max_size?: 2_048)
        optional(:resource_kind).maybe(:string)
        optional(:resource_lifecycle_status).maybe(:string)
        optional(:agent_id).maybe(:string, max_size?: 255)
        optional(:change_set_id).maybe(:string, max_size?: 255)
        optional(:work_item_id).maybe(:string, max_size?: 255)
        optional(:attempt_id).maybe(:string, max_size?: 255)
        optional(:mode).maybe(:string, included_in?: %w[shared exclusive])
      end

      rule(:kind) do
        key.failure("must be resources or active_work_intentions") unless COLLECTION_KINDS.include?(value)
      end

      rule(:after_id) do
        key.failure("must be UUIDv7") if value && !Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:after_updated_at, :after_id) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_updated_at].nil? == values[:after_id].nil?
        next unless values[:after_updated_at]

        key(:after_updated_at).failure("must be a canonical UTC timestamp") unless
          Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end

      rule(:as_of) do
        key.failure("must be a canonical UTC timestamp") unless
          Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(value)
      end

      rule(:resource_kind) do
        key.failure("must be file or directory") if value && !RESOURCE_KINDS.include?(value)
      end

      rule(:resource_lifecycle_status) do
        key.failure("must be registered, current, or inactive") if
          value && !RESOURCE_LIFECYCLES.include?(value)
      end
    end

    class Detail < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:kind).filled(:string)
        required(:id).filled(:string)
        required(:as_of).filled(:string)
      end

      rule(:kind) do
        key.failure("must be resource or work_intention") unless DETAIL_KINDS.include?(value)
      end

      rule(:id) do
        key.failure("must be UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:as_of) do
        key.failure("must be a canonical UTC timestamp") unless
          Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(value)
      end
    end
  end
end
