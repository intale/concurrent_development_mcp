# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class SkillSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(:string, eql?: "SkillRevisionPublished")
        required(:schema_version).filled(:integer, eql?: 3)
        required(:stream_context).filled(:string, eql?: "AgentKnowledge")
        required(:stream_name).filled(:string, eql?: "Skill")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 1)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, included_in?: %w[agent user])
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, included_in?: %w[skill-repository/v1 skill-repository/v2])
      end

      rule(:stream_id) do
        key.failure("must be a valid projected Skill ID") unless ProjectedSkillId.valid?(value)
      end

      rule(:command_id, :actor_id) do
        next if values.values_at(:command_id, :actor_id).all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("command and actor IDs must be valid identifiers")
      end
    end
  end
end
