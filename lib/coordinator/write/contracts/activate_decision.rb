# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ActivateDecision < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: Types::ACTOR_KINDS)
          required(:id).filled(:string)
        end
        required(:decision_id).filled(:string)
        required(:interpretation_id).filled(:string)
        required(:rationale).hash do
          required(:code).filled(:string)
          required(:summary).filled(:string)
        end
      end

      rule(:command_id, :decision_id, :interpretation_id) do
        %i[command_id decision_id interpretation_id].each do |name|
          key(name).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(values[name])
        end
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value[:id])
      end

      rule(:rationale) do
        key([ :rationale, :code ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value[:code])
        unless Text.valid?(value[:summary], max_size: 500)
          key([ :rationale, :summary ]).failure("must be nonblank UTF-8 text of at most 500 characters")
        end
      end
    end
  end
end
