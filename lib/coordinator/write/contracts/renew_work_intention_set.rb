# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RenewWorkIntentionSet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:change_set_id).filled(:string)
        required(:work_item_id).filled(:string)
        required(:attempt_id).filled(:string)
        required(:intention_set_id).filled(:string)
        required(:intentions).array(:hash) do
          required(:resource_id).filled(:string)
          required(:intention_id).filled(:string)
          required(:fencing_token).filled(:integer)
        end
        required(:ttl_seconds).filled(:integer)
      end

      rule(:command_id, :change_set_id, :work_item_id, :attempt_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:intention_set_id) do
        key.failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:intentions) do
        unless (1..32).cover?(value.length)
          key.failure("must contain between 1 and 32 entries")
          next
        end

        value.each_with_index do |reference, index|
          resource_id = reference[:resource_id]
          intention_id = reference[:intention_id]
          token = reference[:fencing_token]
          unless resource_id.is_a?(String) && Types::UUID_V7_PATTERN.match?(resource_id)
            key([ :intentions, index, :resource_id ]).failure("must be a UUIDv7")
          end
          unless intention_id.is_a?(String) && Types::UUID_V7_PATTERN.match?(intention_id)
            key([ :intentions, index, :intention_id ]).failure("must be a UUIDv7")
          end
          unless token.is_a?(Integer) && token >= 1
            key([ :intentions, index, :fencing_token ]).failure("must be at least 1")
          end
        end

        resource_ids = value.filter_map { _1[:resource_id] }
        intention_ids = value.filter_map { _1[:intention_id] }
        key.failure("must not repeat a Resource ID") unless resource_ids.uniq.length == resource_ids.length
        key.failure("must not repeat a work-intention ID") unless intention_ids.uniq.length == intention_ids.length
      end

      rule(:ttl_seconds) do
        key.failure("must be between 30 and 3600") unless (30..3_600).cover?(value)
      end
    end
  end
end
