# frozen_string_literal: true

module Coordinator
  module Contracts
    class AcquireWorkItem < Dry::Validation::Contract
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
        required(:base_snapshots).array(:hash) do
          required(:repository_id).filled(:string)
          required(:commit_oid).value(:string)
        end
      end

      rule(:command_id, :change_set_id, :work_item_id, :attempt_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:base_snapshots) do
        key.failure("must contain at most 100 entries") if value.length > 100

        value.each_with_index do |snapshot, index|
          repository_id = snapshot[:repository_id]
          next unless repository_id.is_a?(String)
          next if Types::REPOSITORY_ID_PATTERN.match?(repository_id)

          key([ :base_snapshots, index, :repository_id ]).failure("must be a valid repository identifier")
        end
      end
    end
  end
end
