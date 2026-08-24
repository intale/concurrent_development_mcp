# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class MergeSnapshotsV1
      PROJECTION = ProjectionDefinition.new(name: "merge-snapshots", version: 1)

      def initialize(
        contract: Contracts::MergeSnapshotSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        snapshots: Repositories::MergeSnapshots.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @snapshots = snapshots
        @processed_events = processed_events
      end

      def call(event)
        snapshot = load_payload(event)
        raise InvalidProjectionSource, "Merge snapshot identity does not match its source stream" unless event.stream.stream_id == snapshot.merge_snapshot_id

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity: ProjectionEventIdentity.from_event(event),
            processed_at: Time.now.utc
          )

          @snapshots.store(event:, snapshot:)
        end
        nil
      end

      private

      def load_payload(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
