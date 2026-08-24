# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RecordReleaseSetVerification < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:release_set_id).filled(:string)
        required(:integration_events).array(
          :hash,
          min_size?: Types::RELEASE_SET_MINIMUM_MEMBERS,
          max_size?: Types::RELEASE_SET_MAXIMUM_MEMBERS
        ) do
          required(:event_id).filled(:string)
          required(:type).filled(:string, eql?: "RepositoryIntegrationRecorded")
          required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
          required(:stream_name).filled(:string, eql?: "ReleaseSet")
          required(:stream_id).filled(:string)
          required(:stream_revision).filled(:integer, gteq?: 1)
        end
        required(:evidence).hash do
          required(:producer).hash do
            required(:name).filled(:string)
            required(:version).filled(:string)
          end
          required(:run_id).filled(:string)
          required(:environment_digest).filled(:string)
          required(:result_digest).filled(:string)
          required(:outcome).filled(:string, included_in?: Types::RELEASE_SET_VERIFICATION_OUTCOMES)
          required(:findings).array(:hash, max_size?: 32) do
            required(:code).filled(:string)
            required(:severity).filled(:string, included_in?: %w[info warning error critical])
            required(:summary).filled(:string)
            required(:repository_id).maybe(:string)
          end
          required(:produced_at).filled(:string)
        end
      end

      rule(:command_id, :release_set_id, :actor) do
        identifiers = [ values[:command_id], values[:release_set_id], values.dig(:actor, :id) ].compact
        key.failure("identifiers must use the canonical format") unless identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }
      end

      rule(:integration_events, :release_set_id) do
        ids = values[:integration_events].map { _1.fetch(:event_id) }
        key.failure("event references must be unique") unless ids.uniq.length == ids.length
        values[:integration_events].each do |reference|
          key.failure("event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(reference.fetch(:event_id))
          key.failure("every event must identify this ReleaseSet") unless reference.fetch(:stream_id) == values[:release_set_id]
        end
      end

      rule(:evidence) do
        producer = value.fetch(:producer)
        if producer.fetch(:name).length > 100 || producer.fetch(:version).length > 100
          key.failure("producer name and version must contain at most 100 characters")
        end
        key.failure("run_id must use the canonical format") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:run_id))
        %i[environment_digest result_digest].each do |field|
          key.failure("#{field} must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value.fetch(field))
        end
        key.failure("produced_at must be a UTC timestamp with microseconds") unless Types::TIMESTAMP_PATTERN.match?(value.fetch(:produced_at))

        value.fetch(:findings).each do |finding|
          key.failure("finding code must be canonical") unless Types::IDENTIFIER_PATTERN.match?(finding.fetch(:code))
          key.failure("finding summary must contain at most 2,000 characters") if finding.fetch(:summary).length > 2_000
          repository_id = finding.fetch(:repository_id)
          if repository_id && !Types::REPOSITORY_ID_PATTERN.match?(repository_id)
            key.failure("finding repository_id must be canonical")
          end
        end
      end

      rule(:evidence) do
        next unless value.fetch(:outcome) == "passed"

        if value.fetch(:findings).any? { %w[error critical].include?(_1.fetch(:severity)) }
          key.failure("passing evidence cannot contain error or critical findings")
        end
      end
    end
  end
end
