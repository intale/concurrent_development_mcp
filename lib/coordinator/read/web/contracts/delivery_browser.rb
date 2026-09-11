# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class DeliveryBrowser
    SORTS = %w[oldest_first newest_first].freeze
    RELEASE_STATUSES = %w[
      prepared integrating verifying verified activated compensation_requested completed
    ].freeze
    BATCH_STATUSES = %w[running cancelling completed completed_with_errors cancelled].freeze
    BATCH_TOOLS = %w[
      skill_publish development_artifact_capture development_artifact_relation_declare
    ].freeze

    class Candidates < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:sort).filled(:string, included_in?: SORTS)
        optional(:change_set_id).maybe(:string)
        optional(:checkpoint_kind).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::CANDIDATE_CHECKPOINT_KINDS
        )
        optional(:after_updated_at).maybe(:string)
        optional(:after_id).maybe(:string)
      end

      rule(:change_set_id, :after_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_updated_at, :after_id) do
        base.failure("cursor coordinates must both be present or absent") unless values[:after_updated_at].nil? == values[:after_id].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end
    end

    class Obligations < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:sort).filled(:string, included_in?: SORTS)
        optional(:change_set_id).maybe(:string)
        optional(:status).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::VERIFICATION_OBLIGATION_STATUSES
        )
        optional(:after_updated_at).maybe(:string)
        optional(:after_id).maybe(:string)
      end

      rule(:change_set_id, :after_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_updated_at, :after_id) do
        base.failure("cursor coordinates must both be present or absent") unless values[:after_updated_at].nil? == values[:after_id].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end
    end

    class Merges < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:sort).filled(:string, included_in?: SORTS)
        optional(:after_updated_at).maybe(:string)
        optional(:after_id).maybe(:string)
      end

      rule(:after_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_updated_at, :after_id) do
        base.failure("cursor coordinates must both be present or absent") unless values[:after_updated_at].nil? == values[:after_id].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end
    end

    class Releases < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:sort).filled(:string, included_in?: SORTS)
        optional(:change_set_id).maybe(:string)
        optional(:status).maybe(:string, included_in?: RELEASE_STATUSES)
        optional(:after_updated_at).maybe(:string)
        optional(:after_id).maybe(:string)
      end

      rule(:change_set_id, :after_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_updated_at, :after_id) do
        base.failure("cursor coordinates must both be present or absent") unless values[:after_updated_at].nil? == values[:after_id].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end
    end

    class Candidate < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:candidate_id).filled(:string)
        optional(:direction).filled(
          :string,
          included_in?: Coordinator::Shared::Types::CANDIDATE_IMPACT_QUERY_DIRECTIONS
        )
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:after_impact_position).maybe(:integer, gteq?: 0)
      end

      rule(:candidate_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Verification < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:obligation_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:after_evidence_updated_at).maybe(:string)
        optional(:after_evidence_id).maybe(:string)
      end

      rule(:after_evidence_id) do
        next unless value

        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:obligation_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_evidence_updated_at, :after_evidence_id) do
        position = values[:after_evidence_updated_at]
        identifier = values[:after_evidence_id]
        base.failure("evidence cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
        key(:after_evidence_updated_at).failure("must be an event timestamp") if position &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(position)
      end
    end

    class Merge < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:merge_snapshot_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:after_authorization_updated_at).maybe(:string)
        optional(:after_authorization_id).maybe(:string)
      end

      rule(:after_authorization_id) do
        next unless value

        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:merge_snapshot_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_authorization_updated_at, :after_authorization_id) do
        position = values[:after_authorization_updated_at]
        identifier = values[:after_authorization_id]
        base.failure("authorization cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
        key(:after_authorization_updated_at).failure("must be an event timestamp") if position &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(position)
      end
    end

    class Release < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:release_set_id).filled(:string)
      end

      rule(:release_set_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Batches < Dry::Validation::Contract
      config.validate_keys = true

      params do
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:sort).filled(:string, included_in?: SORTS)
        optional(:target_tool).maybe(:string, included_in?: BATCH_TOOLS)
        optional(:status).maybe(:string, included_in?: BATCH_STATUSES)
        optional(:after_updated_at).maybe(:string)
        optional(:after_id).maybe(:string)
      end

      rule(:after_id) do
        next unless value

        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:after_updated_at, :after_id) do
        position = values[:after_updated_at]
        identifier = values[:after_id]
        base.failure("batch cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
        key(:after_updated_at).failure("must be an event timestamp") if position &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(position)
      end
    end

    class Batch < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:batch_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:after_index).maybe(:integer, gteq?: 0, lt?: Coordinator::Shared::Types::OPERATION_BATCH_MAXIMUM_ITEMS)
      end

      rule(:batch_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end
    end
  end
end
