# frozen_string_literal: true

module Coordinator
  module Contracts
    class CoordContext < Dry::Validation::Contract
      ROOT_KEYS = %i[change_set_id work_item_id attempt_id].freeze

      config.validate_keys = true

      params do
        optional(:change_set_id).maybe(:string)
        optional(:work_item_id).maybe(:string)
        optional(:attempt_id).maybe(:string)
        optional(:after_command_id).maybe(:string)
        optional(:context_token).maybe(:string)
      end

      rule(*ROOT_KEYS) do
        present = ROOT_KEYS.select { values[_1].is_a?(String) }
        key.failure("must supply exactly one scope root") unless present.one?
      end

      rule(*ROOT_KEYS, :after_command_id) do
        ROOT_KEYS.each do |name|
          identifier = values[name]
          next if identifier.nil? || Types::IDENTIFIER_PATTERN.match?(identifier)

          key(name).failure("must be a valid identifier")
        end

        command_id = values[:after_command_id]
        if command_id && !Types::IDENTIFIER_PATTERN.match?(command_id)
          key(:after_command_id).failure("must be a valid identifier")
        end
      end

      rule(:context_token) do
        next if value.nil? || Types::SHA256_DIGEST_PATTERN.match?(value)

        key.failure("must be a sha256 digest")
      end
    end
  end
end
