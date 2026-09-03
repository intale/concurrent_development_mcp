# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class ResourceSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: %w[ResourceRegistered ResourceBound ResourceUnbound])
        required(:schema_version).filled(:integer, included_in?: [ 1, 2 ])
        required(:stream_context).filled(:string, eql?: "DevelopmentCoordination")
        required(:stream_name).filled(:string, eql?: "Resource")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "resource-identity/v1")
      end

      rule(:stream_id) do
        key.failure("must be a valid Resource UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:command_id, :actor_id) do
        next if values.values_at(:command_id, :actor_id).all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("command and actor IDs must be valid identifiers")
      end

      rule(:event_type, :stream_revision) do
        next unless values[:event_type] == "ResourceRegistered"

        key(:stream_revision).failure("must be zero for ResourceRegistered") unless values[:stream_revision].zero?
      end

      rule(:event_type, :stream_revision) do
        next if values[:event_type] == "ResourceRegistered"

        key(:stream_revision).failure("must follow ResourceRegistered") unless values[:stream_revision].positive?
      end
    end
  end
end
