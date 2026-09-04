# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class ReleaseSetLifecycleSourceEvent < Dry::Validation::Contract
      EVENT_TYPES = %w[
        RepositoryIntegrationRecorded
        ReleaseSetVerificationRecorded
        ReleaseSetActivated
      ].freeze

      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        key.failure("must be a persisted event") if value.stream.nil? || value.stream_revision.nil?
        key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
        unless EVENT_TYPES.include?(value.type) && value.metadata["schema_version"] == 2
          key.failure("must be a supported ReleaseSet lifecycle source at schema version 2")
        end
        stream = value.stream
        unless stream&.context == "DevelopmentIntegration" && stream.stream_name == "ReleaseSet"
          key.failure("must belong to a ReleaseSet stream")
        end
        unless Types::IDENTIFIER_PATTERN.match?(value.data["release_set_id"].to_s) &&
               value.data["release_set_id"] == stream&.stream_id
          key.failure("must identify the same ReleaseSet in stream and payload")
        end
        key.failure("must carry a pg_eventstore trace correlation ID") unless Types::UUID_V7_PATTERN.match?(value.correlation_id.to_s)
      end
    end
  end
end
