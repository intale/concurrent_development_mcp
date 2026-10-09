# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AbandonAttempt < Dry::Validation::Contract
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
        required(:reason).filled(
          :string,
          max_size?: 2_000
        )
      end

      rule(:command_id, :change_set_id, :work_item_id, :attempt_id) do
        %i[command_id change_set_id work_item_id attempt_id].each do |name|
          identifier = values[name]
          next unless identifier.is_a?(String)
          next if Types::IDENTIFIER_PATTERN.match?(identifier)

          key(name).failure("must be a valid identifier")
        end
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end
    end
  end
end
