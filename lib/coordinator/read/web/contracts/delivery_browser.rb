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

    class Catalog < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:sort).filled(:string, included_in?: SORTS)
        optional(:candidate_change_set_id).maybe(:string)
        optional(:candidate_checkpoint_kind).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::CANDIDATE_CHECKPOINT_KINDS
        )
        optional(:candidate_after_position).maybe(:integer, gteq?: 0)
        optional(:candidate_after_id).maybe(:string)
        optional(:obligation_change_set_id).maybe(:string)
        optional(:obligation_status).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::VERIFICATION_OBLIGATION_STATUSES
        )
        optional(:obligation_after_position).maybe(:integer, gteq?: 0)
        optional(:obligation_after_id).maybe(:string)
        optional(:merge_after_position).maybe(:integer, gteq?: 0)
        optional(:merge_after_id).maybe(:string)
        optional(:release_change_set_id).maybe(:string)
        optional(:release_status).maybe(:string, included_in?: RELEASE_STATUSES)
        optional(:release_after_position).maybe(:integer, gteq?: 0)
        optional(:release_after_id).maybe(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      %i[
        candidate_change_set_id candidate_after_id obligation_change_set_id obligation_after_id
        merge_after_id release_change_set_id release_after_id
      ].each do |name|
        rule(name) do
          next unless value

          key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
        end
      end

      %i[candidate obligation merge release].each do |kind|
        rule("#{kind}_after_position".to_sym, "#{kind}_after_id".to_sym) do
          position = values["#{kind}_after_position".to_sym]
          identifier = values["#{kind}_after_id".to_sym]
          base.failure("#{kind} cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
        end
      end
    end

    class Candidate < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:candidate_id).filled(:string)
        optional(:direction).filled(
          :string,
          included_in?: Coordinator::Shared::Types::CANDIDATE_IMPACT_QUERY_DIRECTIONS
        )
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:after_impact_position).maybe(:integer, gteq?: 0)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:candidate_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Verification < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:obligation_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:after_evidence_position).maybe(:integer, gteq?: 0)
        optional(:after_evidence_id).maybe(:string)
      end

      rule(:repository_id, :after_evidence_id) do
        next unless value

        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:obligation_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_evidence_position, :after_evidence_id) do
        position = values[:after_evidence_position]
        identifier = values[:after_evidence_id]
        base.failure("evidence cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
      end
    end

    class Merge < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:merge_snapshot_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:after_authorization_position).maybe(:integer, gteq?: 0)
        optional(:after_authorization_id).maybe(:string)
      end

      rule(:repository_id, :after_authorization_id) do
        next unless value

        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:merge_snapshot_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_authorization_position, :after_authorization_id) do
        position = values[:after_authorization_position]
        identifier = values[:after_authorization_id]
        base.failure("authorization cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
      end
    end

    class Release < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:release_set_id).filled(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
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
        optional(:after_position).maybe(:integer, gteq?: 0)
        optional(:after_id).maybe(:string)
      end

      rule(:after_id) do
        next unless value

        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:after_position, :after_id) do
        position = values[:after_position]
        identifier = values[:after_id]
        base.failure("batch cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
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
