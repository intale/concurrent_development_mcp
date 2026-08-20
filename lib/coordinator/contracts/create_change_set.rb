# frozen_string_literal: true

module Coordinator
  module Contracts
    class CreateChangeSet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: Types::ACTOR_KINDS)
          required(:id).filled(:string)
        end
        required(:change_set_id).filled(:string)
        required(:goal).filled(:string)
        required(:acceptance_criteria).array(:string)
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:change_set_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:goal) do
        key.failure("must be nonblank UTF-8 text of at most 4000 characters") unless Text.valid?(value, max_size: 4_000)
      end

      rule(:acceptance_criteria) do
        unless value.length.between?(1, 100)
          key.failure("must contain between 1 and 100 entries")
          next
        end

        invalid_indexes = value.each_index.reject { |index| Text.valid?(value[index], max_size: 2_000) }
        invalid_indexes.each do |index|
          key([ :acceptance_criteria, index ]).failure(
            "must be nonblank UTF-8 text of at most 2000 characters"
          )
        end

        key.failure("must not contain duplicates") unless value.uniq.length == value.length
      end
    end
  end
end
