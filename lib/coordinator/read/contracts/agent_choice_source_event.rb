# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class AgentChoiceSourceEvent < Dry::Validation::Contract
      REVISION_BY_EVENT_TYPE = {
        "AgentChoiceRecorded" => 0,
        "AgentChoiceAccepted" => 1
      }.freeze
      EVENT_TYPES = REVISION_BY_EVENT_TYPE.keys.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, included_in?: [ 1, 2 ])
        required(:stream_context).filled(:string, eql?: "AgentGovernance")
        required(:stream_name).filled(:string, eql?: "AgentChoice")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "testing-framework-resolution/v1")
      end

      rule(:event_type, :stream_revision) do
        expected = REVISION_BY_EVENT_TYPE.fetch(values[:event_type])
        key(:stream_revision).failure("must match the AgentChoice lifecycle position") unless values[:stream_revision] == expected
      end

      rule(:stream_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
