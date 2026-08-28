# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CoordinationList < Dry::Validation::Contract
      STATUSES = %w[planning active completed].freeze

      config.validate_keys = true

      params do
        required(:scope).filled(:string)
        optional(:repository_id).maybe(:string)
        optional(:statuses).maybe(:array).each(:string)
        optional(:cursor).maybe(:hash) do
          required(:through_last_processed_at).filled(:string)
          required(:after_last_processed_at).filled(:string)
          required(:after_change_set_id).filled(:string)
        end
        optional(:limit).maybe(:integer)
      end

      rule(:scope) do
        unless value.bytesize.between?(1, 500) && value.valid_encoding?
          key.failure("must be valid UTF-8 between 1 and 500 bytes")
        end
      end

      rule(:repository_id) do
        next if value.nil? || Types::UUID_V7_PATTERN.match?(value)

        key.failure("must be a UUIDv7 Repository ID")
      end

      rule(:statuses) do
        next if value.nil?

        key.failure("must contain 1..3 unique statuses") unless value.length.between?(1, 3) && value.uniq == value
        value.each_with_index do |status, index|
          key([ :statuses, index ]).failure("must be planning, active, or completed") unless STATUSES.include?(status)
        end
      end

      rule(:cursor) do
        next unless value

        %i[through_last_processed_at after_last_processed_at].each do |name|
          key([ :cursor, name ]).failure("must be a canonical UTC timestamp") unless
            Types::TIMESTAMP_PATTERN.match?(value.fetch(name))
        end
        unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:after_change_set_id))
          key([ :cursor, :after_change_set_id ]).failure("must be a valid identifier")
        end
        if Types::TIMESTAMP_PATTERN.match?(value.fetch(:through_last_processed_at)) &&
           Types::TIMESTAMP_PATTERN.match?(value.fetch(:after_last_processed_at)) &&
           value.fetch(:after_last_processed_at) > value.fetch(:through_last_processed_at)
          key([ :cursor, :after_last_processed_at ]).failure("must not follow the snapshot bound")
        end
      end

      rule(:limit) do
        next if value.nil? || (1..Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS).cover?(value)

        key.failure("must be between 1 and #{Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS}")
      end
    end
  end
end
