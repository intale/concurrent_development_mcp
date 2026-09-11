# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DecisionGovernanceSourceEvent < Dry::Validation::Contract
      EVENT_SCHEMAS = {
        "DecisionRecorded" => [ "Decision", [ 1, 2 ] ],
        "DecisionActivated" => [ "Decision", [ 1, 2 ] ],
        "DecisionDefinitionCorrected" => [ "Decision", [ 1, 2 ] ],
        "DecisionSlotOpened" => [ "DecisionSlot", [ 1, 2 ] ],
        "DecisionSlotHeadChanged" => [ "DecisionSlot", [ 1, 2 ] ],
        "DecisionPartitionAdvanced" => [ "DecisionPartition", [ 1 ] ],
        "DecisionAddedToPartition" => [ "DecisionPartition", [ 1 ] ],
        "DecisionRemovedFromPartition" => [ "DecisionPartition", [ 1 ] ]
      }.freeze
      EVENT_TYPES = EVENT_SCHEMAS.keys.freeze

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer)
        required(:stream_context).filled(:string, eql?: "HumanGuidance")
        required(:stream_name).filled(:string)
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:actor_kind).filled(:string, included_in?: Types::ACTOR_KINDS)
        required(:actor_id).filled(:string)
      end

      rule(:event_type, :schema_version, :stream_name) do
        expected = EVENT_SCHEMAS[values[:event_type]]
        next unless expected

        expected_stream, expected_versions = expected
        key(:stream_name).failure("must match the Decision governance event type") unless values[:stream_name] == expected_stream
        key(:schema_version).failure("must match the Decision governance fact") unless expected_versions.include?(values[:schema_version])
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
