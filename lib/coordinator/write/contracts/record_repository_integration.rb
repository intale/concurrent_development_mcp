# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RecordRepositoryIntegration < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:release_set_id).filled(:string)
        required(:repository_id).filled(:string)
        required(:attempt_id).filled(:string)
        required(:outcome).filled(:string, included_in?: Types::RELEASE_SET_INTEGRATION_OUTCOMES)
        required(:merge_observation_event).maybe do
          hash do
            required(:event_id).filled(:string)
            required(:type).filled(:string, eql?: "MergeObserved")
            required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
            required(:stream_name).filled(:string, eql?: "MergeSnapshot")
            required(:stream_id).filled(:string)
            required(:stream_revision).filled(:integer, gteq?: 3)
          end
        end
        required(:observation_digest).maybe(:string)
        required(:failure).maybe do
          hash do
            required(:code).filled(:string)
            required(:summary).filled(:string)
            required(:producer).hash do
              required(:name).filled(:string)
              required(:version).filled(:string)
            end
            required(:run_id).filled(:string)
            required(:result_digest).filled(:string)
            required(:occurred_at).filled(:string)
          end
        end
      end

      rule(:command_id, :release_set_id, :attempt_id, :actor) do
        identifiers = [ values[:command_id], values[:release_set_id], values[:attempt_id], values.dig(:actor, :id) ].compact
        key.failure("identifiers must use the canonical format") unless identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }
      end

      rule(:repository_id) do
        key.failure("must be canonical") unless Types::REPOSITORY_ID_PATTERN.match?(value)
      end

      rule(:merge_observation_event) do
        next unless value

        key.failure("event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value.fetch(:event_id))
        key.failure("stream_id must use the canonical format") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:stream_id))
      end

      rule(:outcome, :merge_observation_event, :observation_digest, :failure) do
        if values[:outcome] == "integrated"
          key.failure("integrated outcome requires only observation evidence") unless values[:merge_observation_event] && values[:observation_digest] && values[:failure].nil?
        elsif values[:merge_observation_event] || values[:observation_digest] || values[:failure].nil?
          key.failure("failed outcome requires only failure evidence")
        end
      end

      rule(:observation_digest) do
        next unless value

        key.failure("must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value)
      end

      rule(:failure) do
        next unless value

        key.failure("code must be canonical") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:code))
        key.failure("summary must contain at most 2,000 characters") if value.fetch(:summary).length > 2_000
        producer = value.fetch(:producer)
        if producer.fetch(:name).length > 100 || producer.fetch(:version).length > 100
          key.failure("producer name and version must contain at most 100 characters")
        end
        key.failure("run_id must use the canonical format") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:run_id))
        key.failure("result_digest must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value.fetch(:result_digest))
        key.failure("occurred_at must be a UTC timestamp with microseconds") unless Types::TIMESTAMP_PATTERN.match?(value.fetch(:occurred_at))
      end
    end
  end
end
