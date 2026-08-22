# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class ChangeSetActivationSourceEvent < Dry::Validation::Contract
      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        key.failure("must be a persisted event") if value.stream.nil? || value.stream_revision.nil?
        key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
        key.failure("must be ChangeSetActivated@1") unless activation_schema?(value)
        key.failure("must belong to the ChangeSet stream") unless activation_stream?(value)
        key.failure("must identify the same ChangeSet in stream and payload") unless matching_change_set?(value)
        key.failure("must carry the root command correlation ID") unless valid_correlation?(value)
        key.failure("must carry a pg_eventstore trace correlation ID") unless valid_trace_correlation?(value)
      end

      private

      def activation_schema?(event)
        event.type == "ChangeSetActivated" && event.metadata["schema_version"] == 1
      end

      def activation_stream?(event)
        stream = event.stream
        return false unless stream

        stream.context == "DevelopmentPlanning" && stream.stream_name == "ChangeSet"
      end

      def matching_change_set?(event)
        stream_id = event.stream&.stream_id
        change_set_id = event.data["change_set_id"]

        Types::IDENTIFIER_PATTERN.match?(change_set_id.to_s) && change_set_id == stream_id
      end

      def valid_correlation?(event)
        Types::IDENTIFIER_PATTERN.match?(event.metadata["correlation_id"].to_s)
      end

      def valid_trace_correlation?(event)
        Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)
      end
    end
  end
end
