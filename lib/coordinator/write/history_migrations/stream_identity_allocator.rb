# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class StreamIdentityAllocator
      include Dry::Monads[:result]

      MARKER_PURPOSE = "history-migration-stream"

      def initialize(
        event_store:,
        natural_key_registry: NaturalKeys::Registry.new(event_store:),
        marker_codec: Coordinator::Shared::Markers::CodecV2.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @natural_key_registry = natural_key_registry
        @marker_codec = marker_codec
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(migration_id:, source_config_name:, source_event:, target_stream_context:, target_stream_name:, identity_role:)
        command = command_for(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context:,
          target_stream_name:,
          identity_role:
        )
        encoded = @marker_codec.call(
          purpose: MARKER_PURPOSE,
          components: marker_components(command)
        )
        return Failure(encoded.failure) if encoded.failure?

        marker = encoded.value!.marker
        @natural_key_registry.call(
          selector: selector(marker),
          proposed_stream: @stream_factory.history_migration_identity(command.target_stream_id),
          build_event: -> { build_event(command, marker:, caused_by: source_event) },
          identity_from: ->(event) { identity_from(event, command) }
        ).fmap { allocation(_1) }
      end

      private

      def command_for(
        migration_id:,
        source_config_name:,
        source_event:,
        target_stream_context:,
        target_stream_name:,
        identity_role:
      )
        source_stream = StreamReference.new(
          context: source_event.stream.context,
          stream_name: source_event.stream.stream_name,
          stream_id: source_event.stream.stream_id
        )
        Commands::AllocateHistoryMigrationStreamIdentity.new(
          command_id: @id_generator.uuid_v7,
          actor: Commands::Actor.new(kind: "system", id: "history-migration-dispatcher"),
          event_id: @id_generator.uuid_v7,
          migration_id:,
          source_config_name:,
          source_stream_context: source_event.stream.context,
          source_stream_name: source_event.stream.stream_name,
          source_stream_id: source_event.stream.stream_id,
          source_stream_starting_position: @event_store.stream_starting_position(source_stream),
          target_stream_context:,
          target_stream_name:,
          identity_role:,
          target_stream_id: @id_generator.uuid_v7
        )
      end

      def marker_components(command)
        [
          { dimension: "migration-id", value: command.migration_id },
          { dimension: "source-config", value: command.source_config_name },
          { dimension: "source-position", value: command.source_stream_starting_position.to_s },
          { dimension: "target-context", value: command.target_stream_context },
          { dimension: "target-stream", value: command.target_stream_name },
          { dimension: "identity-role", value: command.identity_role }
        ]
      end

      def selector(marker)
        NaturalKeys::Registry::SelectorV1.new(
          stream_context: "CoordinatorMaintenance",
          stream_name: "HistoryMigrationIdentity",
          event_type: "HistoryMigrationStreamIdentityAllocated",
          marker:
        )
      end

      def build_event(command, marker:, caused_by:)
        @event_factory.build!(
          event: Events::HistoryMigrationStreamIdentityAllocatedV1.new(event_attributes(command)),
          event_id: command.event_id,
          metadata: EventMetadata.new(
            command_id: command.command_id,
            actor_kind: command.actor.kind,
            actor_id: command.actor.id,
            recorded_by: "coordinator",
            policy_version: "history-migration-stream-identity/v1"
          ),
          markers: [ marker, "history-migration:#{command.migration_id}", "target-stream:#{command.target_stream_id}" ],
          caused_by:
        )
      end

      def identity_from(event, command)
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        return unless identity_tuple(payload) == identity_tuple(command)

        payload.target_stream_id
      rescue KeyError, ArgumentError
        nil
      end

      def identity_tuple(value)
        %i[
          migration_id source_config_name source_stream_context source_stream_name
          source_stream_id source_stream_starting_position target_stream_context
          target_stream_name identity_role
        ].map { value.public_send(_1) }
      end

      def event_attributes(command)
        {
          migration_id: command.migration_id,
          source_config_name: command.source_config_name,
          source_stream_context: command.source_stream_context,
          source_stream_name: command.source_stream_name,
          source_stream_id: command.source_stream_id,
          source_stream_starting_position: command.source_stream_starting_position,
          target_stream_context: command.target_stream_context,
          target_stream_name: command.target_stream_name,
          identity_role: command.identity_role,
          target_stream_id: command.target_stream_id
        }
      end

      def allocation(resolution)
        payload = @schema_registry.load(
          type: resolution.event.type,
          schema_version: resolution.event.metadata.fetch("schema_version"),
          data: resolution.event.data
        )
        StreamAllocationV1.new(
          target_stream: StreamReference.new(
            context: payload.target_stream_context,
            stream_name: payload.target_stream_name,
            stream_id: payload.target_stream_id
          ),
          allocation_event: resolution.event,
          outcome: resolution.outcome
        )
      end
    end
  end
end
