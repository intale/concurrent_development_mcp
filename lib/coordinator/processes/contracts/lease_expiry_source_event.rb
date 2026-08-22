# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class LeaseExpirySourceEvent < Dry::Validation::Contract
      SUPPORTED_TYPES = %w[ResourceLeaseAcquired ResourceLeaseRenewed].freeze

      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      def initialize(compound_marker_builder: CompoundMarkerBuilder.new)
        super()
        @compound_marker_builder = compound_marker_builder
      end

      rule(:event) do
        key.failure("must be a persisted event") unless persisted?(value)
        key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
        key.failure("must be a supported ResourceLease lifecycle source at schema 1") unless supported_schema?(value)
        key.failure("must belong to its ResourceLease stream") unless matching_resource_stream?(value)
        key.failure("must carry command provenance") unless matching_provenance?(value)
        key.failure("must carry its complete resource-routing markers") unless matching_markers?(value)
        key.failure("must carry a pg_eventstore trace correlation ID") unless valid_trace_correlation?(value)
      end

      private

      def persisted?(event)
        event.stream && event.stream_revision && event.stream_revision >= 0 && event.global_position
      end

      def supported_schema?(event)
        SUPPORTED_TYPES.include?(event.type) && event.metadata["schema_version"] == 1
      end

      def matching_resource_stream?(event)
        stream = event.stream
        resource_key_hash = event.data["resource_key_hash"]
        return false unless stream && Types::SHA256_DIGEST_PATTERN.match?(resource_key_hash.to_s)

        stream.context == "DevelopmentCoordination" &&
          stream.stream_name == "ResourceLease" &&
          stream.stream_id == resource_key_hash
      end

      def matching_provenance?(event)
        command_id = event.metadata["command_id"]

        Types::IDENTIFIER_PATTERN.match?(command_id.to_s) &&
          event.metadata["policy_version"] == Coordinator::Write::ResourceKeyDocumentV1::POLICY_VERSION
      end

      def matching_markers?(event)
        data = event.data
        components = [
          "repository:#{data['repository_id']}",
          "resource-kind:#{data['resource_kind']}",
          "resource-key-hash:#{data['resource_key_hash']}"
        ]
        compound = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "resource-identity",
            components:
          )
        )
        expected = [
          "change-set:#{data['change_set_id']}",
          "work-item:#{data['work_item_id']}",
          "attempt:#{data['attempt_id']}",
          "command:#{event.metadata['command_id']}",
          "lease-set:#{data['lease_set_id']}",
          *components,
          compound.marker
        ].uniq.sort

        event.markers == expected
      end

      def valid_trace_correlation?(event)
        Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)
      end
    end
  end
end
