# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class ResourceBoundaryMaintenance
      class Rejected < StandardError; end

      class SourceContract < Dry::Validation::Contract
        EVENT_TYPES = Coordinator::Write::EventQueries::RESOURCE_LEASE_LIFECYCLE_EVENT_TYPES

        params do
          required(:event).value(Types.Instance(PgEventstore::Event))
        end

        rule(:event) do
          key.failure("must be a persisted event") unless value.stream_revision && value.global_position
          key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
          unless EVENT_TYPES.include?(value.type) && value.metadata["schema_version"] == 2
            key.failure("must be a ResourceLease lifecycle event at schema 2")
          end
          stream = value.stream
          unless stream&.context == "DevelopmentCoordination" &&
                 stream.stream_name == "ResourceLease" &&
                 stream.stream_id == value.data["resource_id"]
            key.failure("must belong to its ResourceLease stream")
          end
          key.failure("must carry command provenance") unless Types::IDENTIFIER_PATTERN.match?(value.metadata["command_id"].to_s)
          key.failure("must carry a trace correlation ID") unless Types::UUID_V7_PATTERN.match?(value.correlation_id.to_s)
        end
      end

      SYSTEM_ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "resource-boundary-maintenance-v1"
      )

      def initialize(
        event_store:,
        contract: SourceContract.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        marker_builder: Coordinator::Write::RepositoryMarkerBuilder.new,
        operation: Coordinator::Write::Operations::ExecuteRollResourceBoundaryEpoch.new(event_store:)
      )
        @contract = contract
        @schema_registry = schema_registry
        @marker_builder = marker_builder
        @operation = operation
      end

      def call(event)
        validated = @contract.call(event:)
        raise Rejected, validated.errors.to_h.inspect if validated.failure?

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        boundary_markers(payload).each_with_index do |marker, boundary_index|
          result = @operation.call_command(
            command(event:, payload:, marker:, boundary_index:),
            caused_by: event
          )
          next if result.success?

          failure = result.failure
          raise Rejected, "Boundary rollover failed: #{failure.code} - #{failure.message}"
        end
        nil
      rescue Dry::Struct::Error,
             Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise Rejected, error.message
      end

      private

      def boundary_markers(payload)
        @marker_builder.resource_event_markers(
          repository_id: payload.repository_id,
          resource_kind: payload.resource_kind,
          resource_path: payload.resource_path
        ).sort_by(&:b)
      end

      def command(event:, payload:, marker:, boundary_index:)
        Coordinator::Write::Commands::RollResourceBoundaryEpoch.new(
          command_id: InternalCommandIdBuilder.call(
            "resource-boundary-rollover:v2:#{event.id}:#{boundary_index}"
          ),
          actor: SYSTEM_ACTOR,
          repository_id: payload.repository_id,
          boundary_marker: marker,
          source_event_id: event.id,
          source_global_position: event.global_position
        )
      end
    end
  end
end
