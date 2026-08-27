# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CoordContext < Dry::Validation::Contract
      ROOT_KEYS = %i[change_set_id work_item_id attempt_id].freeze

      config.validate_keys = true

      params do
        optional(:change_set_id).maybe(:string)
        optional(:work_item_id).maybe(:string)
        optional(:attempt_id).maybe(:string)
        optional(:context_token).maybe(:string)
      end

      rule(*ROOT_KEYS) do
        present = ROOT_KEYS.select { values[_1].is_a?(String) }
        key.failure("must supply exactly one scope root") unless present.one?
      end

      rule(*ROOT_KEYS) do
        ROOT_KEYS.each do |name|
          identifier = values[name]
          next if identifier.nil? || Types::IDENTIFIER_PATTERN.match?(identifier)

          key(name).failure("must be a valid identifier")
        end
      end

      rule(:context_token) do
        next if value.nil? || Types::SHA256_DIGEST_PATTERN.match?(value)

        key.failure("must be a sha256 digest")
      end

      class AttemptList < Dry::Validation::Contract
        config.validate_keys = true

        params do
          required(:work_item_id).filled(:string)
          optional(:after_authorized_global_position).maybe(:integer)
          optional(:limit).maybe(:integer)
        end

        rule(:work_item_id) do
          key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
        end

        rule(:after_authorized_global_position) do
          key.failure("must be non-negative") if value && value.negative?
        end

        rule(:limit) do
          key.failure("must be between 1 and 100") if value && !(1..100).cover?(value)
        end
      end
    end
  end
end
