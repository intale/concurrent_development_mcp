# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CompleteWorkItem < Dry::Validation::Contract
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
        required(:candidate_id).filled(:string)
        required(:produced_outputs).array(:hash) do
          required(:kind).filled(:string, included_in?: Types::WORK_ITEM_OUTPUT_KINDS)
          required(:key).filled(:string)
        end
      end

      rule(:command_id, :change_set_id, :work_item_id, :attempt_id, :candidate_id) do
        %i[command_id change_set_id work_item_id attempt_id candidate_id].each do |name|
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

      rule(:produced_outputs) do
        if value.length > Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT
          key.failure("must contain at most #{Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT} outputs")
          next
        end

        identities = value.map { [ _1[:kind], _1[:key] ] }
        key.failure("must not contain duplicate outputs") unless identities.uniq.length == identities.length

        value.each_with_index do |output, index|
          output_key = output[:key]
          next unless output_key.is_a?(String)
          next if Types::IDENTIFIER_PATTERN.match?(output_key)

          key([ :produced_outputs, index, :key ]).failure("must be a valid identifier")
        end
      end
    end
  end
end
