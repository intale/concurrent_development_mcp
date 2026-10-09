# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class RepositorySourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: %w[
          RepositoryRegistered RepositoryDisplayNameChanged RepositoryPathAdded RepositoryPathRemoved
          RepositoryRemoteAdded RepositoryRemoteRemoved
        ])
        required(:schema_version).filled(:integer)
        required(:stream_context).filled(:string, eql?: "DevelopmentPlanning")
        required(:stream_name).filled(:string, eql?: "Repository")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "repository-registration/v1")
      end

      rule(:stream_id) do
        key.failure("must be a valid Repository UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:event_type, :schema_version, :stream_revision) do
        expected = values[:event_type] == "RepositoryRegistered" ? [ 2 ] : [ 1 ]
        key(:schema_version).failure("unsupported Repository event schema") unless expected.include?(values[:schema_version])
        if values[:event_type] == "RepositoryRegistered"
          key(:stream_revision).failure("must be zero for RepositoryRegistered") unless values[:stream_revision].zero?
        end
      end

      rule(:command_id, :actor_id) do
        next if values.values_at(:command_id, :actor_id).all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("command and actor IDs must be valid identifiers")
      end
    end
  end
end
