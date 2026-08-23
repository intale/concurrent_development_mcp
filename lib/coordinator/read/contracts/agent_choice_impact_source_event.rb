# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class AgentChoiceImpactSourceEvent < Dry::Validation::Contract
      STREAM_BY_EVENT_TYPE = {
        "AgentChoiceImpactAssessed" => [ "AgentChoiceImpact", 0 ],
        "AgentChoiceInvalidatedByDecision" => [ "AgentChoice", 2 ]
      }.freeze
      EVENT_TYPES = STREAM_BY_EVENT_TYPE.keys.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "AgentGovernance")
        required(:stream_name).filled(:string)
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "system")
        required(:actor_id).filled(:string, eql?: "agent-choice-decision-impact")
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "agent-choice-decision-impact/v1")
      end

      rule(:event_type, :stream_name, :stream_revision) do
        expected_name, expected_revision = STREAM_BY_EVENT_TYPE.fetch(values[:event_type])
        unless values[:stream_name] == expected_name && values[:stream_revision] == expected_revision
          key(:stream_name).failure("must match the AgentChoice impact lifecycle position")
        end
      end

      rule(:stream_id, :command_id) do
        unless Types::IDENTIFIER_PATTERN.match?(values[:stream_id]) &&
               Types::IDENTIFIER_PATTERN.match?(values[:command_id])
          key(:stream_id).failure("stream and command IDs must be valid identifiers")
        end
      end
    end
  end
end
