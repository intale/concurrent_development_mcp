# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class BuildProgressSourceEvent < Dry::Validation::Contract
      EVENT_STREAMS = {
        "WorkItemCandidateSelected" => [ "DevelopmentExecution", "WorkItem", "work_item_id" ],
        "WorkItemCompleted" => [ "DevelopmentExecution", "WorkItem", "work_item_id" ],
        "RepositoryIntegrationRecorded" => [ "DevelopmentIntegration", "ReleaseSet", "release_set_id" ],
        "ReleaseSetVerificationRecorded" => [ "DevelopmentIntegration", "ReleaseSet", "release_set_id" ],
        "ReleaseSetCompleted" => [ "DevelopmentIntegration", "ReleaseSet", "release_set_id" ]
      }.freeze

      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        expected = EVENT_STREAMS[value.type]
        unless expected
          key.failure("type is not supported by build-progress-v1")
          next
        end

        context, stream_name, identity_key = expected
        key.failure("event ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(value.id.to_s)
        unless Types::UUID_V7_PATTERN.match?(value.correlation_id.to_s)
          key.failure("event must carry a pg_eventstore trace correlation ID")
        end
        unless allowed_schema_versions(value.type).include?(value.metadata["schema_version"])
          key.failure("schema version is not supported")
        end
        unless value.stream.context == context && value.stream.stream_name == stream_name
          key.failure("event stream does not match its type")
        end
        key.failure("event payload identity does not match its stream") unless value.data[identity_key] == value.stream.stream_id
      end

      private

      def allowed_schema_versions(type)
        return [ 1, 2 ] if %w[WorkItemCandidateSelected WorkItemCompleted].include?(type)

        [ 2 ]
      end
    end
  end
end
