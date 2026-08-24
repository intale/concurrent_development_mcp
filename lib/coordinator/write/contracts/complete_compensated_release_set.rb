# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CompleteCompensatedReleaseSet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:release_set_id).filled(:string)
        required(:compensation_request_event).hash do
          required(:event_id).filled(:string)
          required(:type).filled(:string, eql?: "ReleaseSetCompensationRequested")
          required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
          required(:stream_name).filled(:string, eql?: "ReleaseSet")
          required(:stream_id).filled(:string)
          required(:stream_revision).filled(:integer, gteq?: 1)
        end
        required(:evidence).array(:hash, min_size?: 1, max_size?: Types::RELEASE_SET_MAXIMUM_MEMBERS) do
          required(:repository_id).filled(:string)
          required(:integration_event).hash do
            required(:event_id).filled(:string)
            required(:type).filled(:string, eql?: "RepositoryIntegrationRecorded")
            required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
            required(:stream_name).filled(:string, eql?: "ReleaseSet")
            required(:stream_id).filled(:string)
            required(:stream_revision).filled(:integer, gteq?: 1)
          end
          required(:action).filled(:string, included_in?: Types::RELEASE_SET_COMPENSATION_ACTIONS)
          required(:external_reference).filled(:string)
          required(:result_digest).filled(:string)
          required(:producer).hash do
            required(:name).filled(:string)
            required(:version).filled(:string)
          end
          required(:run_id).filled(:string)
          required(:compensated_at).filled(:string)
        end
      end

      rule(:command_id, :release_set_id, :actor) do
        identifiers = [ values[:command_id], values[:release_set_id], values.dig(:actor, :id) ].compact
        key.failure("identifiers must use the canonical format") unless identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }
      end

      rule(:compensation_request_event, :release_set_id) do
        key.failure("event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value.fetch(:event_id))
        key.failure("event must identify this ReleaseSet") unless value.fetch(:stream_id) == values[:release_set_id]
      end

      rule(:evidence, :release_set_id) do
        repositories = value.map { _1.fetch(:repository_id) }
        event_ids = value.map { _1.fetch(:integration_event).fetch(:event_id) }
        key.failure("repository evidence must be unique") unless repositories.uniq.length == repositories.length
        key.failure("integration event evidence must be unique") unless event_ids.uniq.length == event_ids.length

        value.each do |item|
          key.failure("repository_id must be canonical") unless Types::REPOSITORY_ID_PATTERN.match?(item.fetch(:repository_id))
          reference = item.fetch(:integration_event)
          key.failure("integration event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(reference.fetch(:event_id))
          key.failure("integration event must identify this ReleaseSet") unless reference.fetch(:stream_id) == values[:release_set_id]
          key.failure("external_reference must contain at most 1,000 characters") if item.fetch(:external_reference).length > 1_000
          key.failure("result_digest must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(item.fetch(:result_digest))
          producer = item.fetch(:producer)
          if producer.fetch(:name).length > 100 || producer.fetch(:version).length > 100
            key.failure("producer name and version must contain at most 100 characters")
          end
          key.failure("run_id must be canonical") unless Types::IDENTIFIER_PATTERN.match?(item.fetch(:run_id))
          unless Types::TIMESTAMP_PATTERN.match?(item.fetch(:compensated_at))
            key.failure("compensated_at must be a UTC timestamp with microseconds")
          end
        end
      end
    end
  end
end
