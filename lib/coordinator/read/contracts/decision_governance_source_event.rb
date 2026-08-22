# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DecisionGovernanceSourceEvent < Dry::Validation::Contract
      STREAM_BY_EVENT_TYPE = {
        "DecisionRecorded" => "Decision",
        "DecisionActivated" => "Decision",
        "DecisionSlotOpened" => "DecisionSlot",
        "DecisionSlotHeadChanged" => "DecisionSlot",
        "DecisionPartitionAdvanced" => "DecisionPartition"
      }.freeze
      EVENT_TYPES = STREAM_BY_EVENT_TYPE.keys.freeze

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "HumanGuidance")
        required(:stream_name).filled(:string)
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:actor_kind).filled(:string, included_in?: Types::ACTOR_KINDS)
        required(:actor_id).filled(:string)
      end

      rule(:event_type, :stream_name) do
        expected = STREAM_BY_EVENT_TYPE.fetch(values[:event_type])
        key(:stream_name).failure("must match the Decision governance event type") unless values[:stream_name] == expected
      end

      rule(:stream_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
