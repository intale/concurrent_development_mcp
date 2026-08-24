# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class VerificationObligationSourceEvent < Dry::Validation::Contract
      EVENT_TYPES = [ "VerificationObligationCreated", "VerificationObligationClaimed" ].freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "VerificationObligation")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, included_in?: %w[agent system])
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string)
      end

      rule(:stream_id, :command_id) do
        identifiers = values.values_at(:stream_id, :command_id)
        next if identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("stream and command IDs must be valid identifiers")
      end

      rule(:event_type, :stream_id, :stream_revision, :command_id, :actor_kind, :actor_id, :policy_version) do
        valid = case values[:event_type]
        when "VerificationObligationCreated"
          values[:stream_revision].zero? &&
            values[:stream_id] == values[:command_id] &&
            values[:actor_kind] == "system" &&
            values[:actor_id] == "candidate-impact-obligation-policy" &&
            values[:policy_version] == "candidate-compatibility-obligation/v1"
        when "VerificationObligationClaimed"
          values[:stream_revision].positive? &&
            values[:actor_kind] == "agent" &&
            values[:policy_version] == "verification-obligation-claim/v1"
        else
          false
        end
        key(:event_type).failure("must use the exact event-specific source contract") unless valid
      end
    end
  end
end
