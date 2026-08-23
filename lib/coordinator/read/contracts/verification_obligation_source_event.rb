# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class VerificationObligationSourceEvent < Dry::Validation::Contract
      EVENT_TYPES = [ "VerificationObligationCreated" ].freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "VerificationObligation")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, eql?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "system")
        required(:actor_id).filled(:string, eql?: "candidate-impact-obligation-policy")
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "candidate-compatibility-obligation/v1")
      end

      rule(:stream_id, :command_id) do
        identifiers = values.values_at(:stream_id, :command_id)
        next if identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("stream and command IDs must be valid identifiers")
      end

      rule(:stream_id, :command_id) do
        next if values[:stream_id] == values[:command_id]

        key(:command_id).failure("must identify the VerificationObligation stream")
      end
    end
  end
end
