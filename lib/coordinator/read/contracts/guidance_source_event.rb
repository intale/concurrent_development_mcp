# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class GuidanceSourceEvent < Dry::Validation::Contract
      EVENT_SCHEMAS = {
        "UserUtteranceRecorded" => [ 1, 2 ],
        "UserUtteranceForwardedByAgent" => [ 1, 2 ],
        "GuidanceMessageAnchored" => [ 1 ]
      }.freeze
      EVENT_TYPES = EVENT_SCHEMAS.keys.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer)
        required(:stream_context).filled(:string, eql?: "HumanGuidance")
        required(:stream_name).filled(:string, eql?: "Conversation")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:actor_kind).filled(:string, included_in?: Types::ACTOR_KINDS)
        required(:actor_id).filled(:string)
      end

      rule(:event_type, :schema_version) do
        expected = EVENT_SCHEMAS[values[:event_type]]
        key(:schema_version).failure("must match the guidance fact") unless expected&.include?(values[:schema_version])
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
