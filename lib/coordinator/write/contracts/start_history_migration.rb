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
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::PUBLIC_COMMAND_ID_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end
    end
  end
end
