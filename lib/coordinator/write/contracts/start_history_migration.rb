# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class StartHistoryMigration < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: Types::ACTOR_KINDS)
          required(:id).filled(:string)
        end
        optional(:page_size).filled(
          :integer,
          gteq?: 1,
          lteq?: Types::HISTORY_MIGRATION_PAGE_SIZE_MAXIMUM
        )
        optional(:source_upper_position).filled(:integer, gteq?: 0)
        optional(:source_after_position).filled(:integer, gteq?: 0)
        optional(:source_command_ids).array(:string, min_size?: 1, max_size?: 100)
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::PUBLIC_COMMAND_ID_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:source_after_position, :source_upper_position, :source_command_ids) do
        next unless values.key?(:source_after_position) || values.key?(:source_command_ids)

        unless %i[source_after_position source_upper_position source_command_ids].all? { values.key?(_1) }
          key.failure("a suffix requires an explicit lower bound, upper bound, and command selection")
          next
        end
        key.failure("must be below source_upper_position") unless values[:source_after_position] < values[:source_upper_position]
        ids = values[:source_command_ids]
        key(:source_command_ids).failure("must contain unique UUIDv7 command IDs") unless ids.uniq == ids && ids.all? { Types::UUID_V7_PATTERN.match?(_1) }
      end
    end
  end
end
