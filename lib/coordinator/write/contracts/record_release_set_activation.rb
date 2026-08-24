# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RecordReleaseSetActivation < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:release_set_id).filled(:string)
        required(:verification_event).hash do
          required(:event_id).filled(:string)
          required(:type).filled(:string, eql?: "ReleaseSetVerificationRecorded")
          required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
          required(:stream_name).filled(:string, eql?: "ReleaseSet")
          required(:stream_id).filled(:string)
          required(:stream_revision).filled(:integer, gteq?: 1)
        end
        required(:verification_digest).filled(:string)
        required(:activation_point).hash do
          required(:kind).filled(:string, included_in?: Types::RELEASE_SET_ACTIVATION_POINT_KINDS)
          required(:environment).filled(:string)
          required(:external_reference).filled(:string)
          required(:state_digest).filled(:string)
          required(:producer).hash do
            required(:name).filled(:string)
            required(:version).filled(:string)
          end
          required(:run_id).filled(:string)
          required(:activated_at).filled(:string)
        end
      end

      rule(:command_id, :release_set_id, :actor) do
        identifiers = [ values[:command_id], values[:release_set_id], values.dig(:actor, :id) ].compact
        key.failure("identifiers must use the canonical format") unless identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }
      end

      rule(:verification_event, :release_set_id) do
        key.failure("event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value.fetch(:event_id))
        key.failure("event must identify this ReleaseSet") unless value.fetch(:stream_id) == values[:release_set_id]
      end

      rule(:verification_digest) do
        key.failure("must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value)
      end

      rule(:activation_point) do
        producer = value.fetch(:producer)
        if producer.fetch(:name).length > 100 || producer.fetch(:version).length > 100
          key.failure("producer name and version must contain at most 100 characters")
        end
        key.failure("environment must be canonical") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:environment))
        key.failure("external_reference must contain at most 1,000 characters") if value.fetch(:external_reference).length > 1_000
        key.failure("state_digest must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value.fetch(:state_digest))
        key.failure("run_id must be canonical") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:run_id))
        key.failure("activated_at must be a UTC timestamp with microseconds") unless Types::TIMESTAMP_PATTERN.match?(value.fetch(:activated_at))
      end
    end
  end
end
