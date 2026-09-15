# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CorrelationAllocator
      include Dry::Monads[:result]

      MARKER_PURPOSE = "history-migration-correlation"

      def initialize(
        event_store:,
        natural_key_registry: NaturalKeys::Registry.new(event_store:),
        marker_codec: Coordinator::Shared::Markers::CodecV2.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @natural_key_registry = natural_key_registry
        @marker_codec = marker_codec
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(migration_id:, source_config_name:, source_event:)
        command = command_for(migration_id:, source_config_name:, source_event:)
        encoded = @marker_codec.call(purpose: MARKER_PURPOSE, components: marker_components(command))
        return Failure(encoded.failure) if encoded.failure?

        marker = encoded.value!.marker
        @natural_key_registry.call(
          selector: selector(marker),
          proposed_stream: @stream_factory.history_migration_correlation(command.target_correlation_id),
          build_event: -> { build_event(command, marker:, caused_by: source_event) },
          identity_from: ->(event) { identity_from(event, command) }
        ).fmap { allocation(_1) }
      end

      private

      def command_for(migration_id:, source_config_name:, source_event:)
        Commands::AllocateHistoryMigrationCorrelation.new(
          command_id: @id_generator.uuid_v7,
          actor: Commands::Actor.new(kind: "system", id: "history-migration-dispatcher"),
          event_id: @id_generator.uuid_v7,
          migration_id:,
          source_config_name:,
          source_correlation_id: source_event.correlation_id,
          target_correlation_id: @id_generator.uuid_v7
        )
      end

      def marker_components(command)
        components = [
          { dimension: "migration-id", value: command.migration_id },
          { dimension: "source-config", value: command.source_config_name }
        ]
        components << { dimension: "source-correlation", value: command.source_correlation_id }
        components
      end

      def selector(marker)
        NaturalKeys::Registry::SelectorV1.new(
          stream_context: "CoordinatorMaintenance",
          stream_name: "HistoryMigrationCorrelation",
          event_type: "HistoryMigrationCorrelationAllocated",
          marker:
        )
      end

      def build_event(command, marker:, caused_by:)
        @event_factory.build!(
          event: Events::HistoryMigrationCorrelationAllocatedV1.new(event_attributes(command)),
          event_id: command.event_id,
          metadata: EventMetadata.new(
            command_id: command.command_id,
            actor_kind: command.actor.kind,
            actor_id: command.actor.id,
            recorded_by: "coordinator",
            policy_version: "history-migration-correlation/v1"
          ),
          markers: [ marker, "history-migration:#{command.migration_id}",
                     "target-correlation:#{command.target_correlation_id}" ],
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

        payload.target_correlation_id
      rescue KeyError, ArgumentError
        nil
      end

      def identity_tuple(value)
        %i[
          migration_id source_config_name source_correlation_id
        ].map { value.public_send(_1) }
      end

      def event_attributes(command)
        {
          migration_id: command.migration_id,
          source_config_name: command.source_config_name,
          source_correlation_id: command.source_correlation_id,
          target_correlation_id: command.target_correlation_id
        }
      end

      def allocation(resolution)
        payload = @schema_registry.load(
          type: resolution.event.type,
          schema_version: resolution.event.metadata.fetch("schema_version"),
          data: resolution.event.data
        )
        CorrelationAllocationV1.new(
          target_correlation_id: payload.target_correlation_id,
          allocation_event: resolution.event,
          outcome: resolution.outcome
        )
      end
    end
  end
end
