# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class LeaseExpirySourceEvent < Dry::Validation::Contract
      SUPPORTED_TYPES = %w[ResourceLeaseAcquired ResourceLeaseRenewed].freeze

      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      def initialize(
        compound_marker_builder: CompoundMarkerBuilder.new,
        repository_marker_builder: Coordinator::Write::RepositoryMarkerBuilder.new
      )
        super()
        @compound_marker_builder = compound_marker_builder
        @repository_marker_builder = repository_marker_builder
      end

      rule(:event) do
        key.failure("must be a persisted event") unless persisted?(value)
        key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
        key.failure("must be a supported ResourceLease lifecycle source") unless supported_schema?(value)
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
        SUPPORTED_TYPES.include?(event.type) && [ 1, 2 ].include?(event.metadata["schema_version"])
      end

      def matching_resource_stream?(event)
        stream = event.stream
        identity = if event.metadata["schema_version"] == 2
                     event.data["resource_id"]
                   else
                     event.data["resource_key_hash"]
                   end
        return false unless stream && identity

        stream.context == "DevelopmentCoordination" &&
          stream.stream_name == "ResourceLease" &&
          stream.stream_id == identity
      end

      def matching_provenance?(event)
        command_id = event.metadata["command_id"]

        expected_policy = if event.metadata["schema_version"] == 2
                            Coordinator::Write::LeaseResourceV2::POLICY_VERSION
                          else
                            Coordinator::Write::ResourceKeyDocumentV3::POLICY_VERSION
                          end

        Types::IDENTIFIER_PATTERN.match?(command_id.to_s) && event.metadata["policy_version"] == expected_policy
      end

      def matching_markers?(event)
        data = event.data
        scope_markers = event.markers.grep(/\Ascope:/)
        return false unless scope_markers.one?

        scope = scope_markers.fetch(0)
        repository = "repository:#{data['repository_id']}"
        repository_components = [
          scope,
          repository
        ]
        scoped_repository = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "scoped-repository",
            components: repository_components
          )
        )
        expected = [
          "change-set:#{data['change_set_id']}",
          "work-item:#{data['work_item_id']}",
          "attempt:#{data['attempt_id']}",
          "command:#{event.metadata['command_id']}",
          "lease-set:#{data['lease_set_id']}",
          *repository_components,
          scoped_repository.marker,
          *resource_identity_markers(event),
          *@repository_marker_builder.resource_event_markers(
            repository_id: data.fetch("repository_id"),
            resource_kind: data.fetch("resource_kind"),
            resource_path: data.fetch("resource_path")
          )
        ].uniq.sort

        event.markers == expected
      end

      def resource_identity_markers(event)
        data = event.data
        return [
          "resource:#{data['resource_id']}",
          "resource-kind:#{data['resource_kind']}"
        ] if event.metadata["schema_version"] == 2

        components = [
          event.markers.grep(/\Ascope:/).sole,
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
        components.drop(2) + [ compound.marker ]
      end

      def valid_trace_correlation?(event)
        Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)
      end
    end
  end
end
