# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceTracePlanner
      include Dry::Monads[:result]

      MARKER_PURPOSE = "history-migration-source-trace"

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

      def call(migration_id:, source_event:, target_plans:)
        endpoint = if target_plans.empty?
          parent = causal_parent(migration_id:, source_event:)
          return parent if parent.failure?

          parent.value!
        else
          target_plans.last.target_event
        end

        command = command_for(
          migration_id:,
          source_event:,
          target_endpoint: endpoint
        )
        encoded = marker_for(migration_id:, source_event_id: source_event.id)
        return Failure(encoded.failure) if encoded.failure?

        marker = encoded.value!.marker
        @natural_key_registry.call(
          selector: selector(marker),
          proposed_stream: @stream_factory.history_migration_source_trace(command.trace_id),
          build_event: -> { build_event(command, marker:, caused_by: source_event) },
          identity_from: ->(event) { identity_from(event, command) }
        ).fmap { trace(_1) }
      end

      def causal_parent(migration_id:, source_event:)
        source_causation_id = source_event.causation_id
        return Success(nil) unless source_causation_id

        result = find(migration_id:, source_event_id: source_causation_id)
        return result if result.failure?
        return Success(result.value!.target_endpoint) if result.value!

        Failure(unresolved(source_event, source_causation_id:))
      end

      def find(migration_id:, source_event_id:)
        encoded = marker_for(migration_id:, source_event_id:)
        return Failure(encoded.failure) if encoded.failure?

        marker = encoded.value!.marker
        @natural_key_registry.find(
          selector: selector(marker),
          identity_from: ->(event) { find_identity(event, migration_id:, source_event_id:) }
        ).fmap { _1 && trace(_1) }
      end

      private

      def command_for(migration_id:, source_event:, target_endpoint:)
        Commands::ResolveHistoryMigrationSourceTrace.new(
          command_id: @id_generator.uuid_v7,
          actor: Commands::Actor.new(kind: "system", id: "history-migration-planner"),
          event_id: @id_generator.uuid_v7,
          trace_id: @id_generator.uuid_v7,
          migration_id:,
          source_event_id: source_event.id,
          source_global_position: source_event.global_position,
          source_causation_id: source_event.causation_id,
          target_endpoint:
        )
      end

      def marker_for(migration_id:, source_event_id:)
        @marker_codec.call(
          purpose: MARKER_PURPOSE,
          components: [
            { dimension: "migration-id", value: migration_id },
            { dimension: "source-event", value: source_event_id }
          ]
        )
      end

      def selector(marker)
        NaturalKeys::Registry::SelectorV1.new(
          stream_context: "CoordinatorMaintenance",
          stream_name: "HistoryMigrationSourceTrace",
          event_type: "HistoryMigrationSourceTraceResolved",
          marker:
        )
      end

      def build_event(command, marker:, caused_by:)
        markers = [
          marker,
          "history-migration:#{command.migration_id}",
          "migration-source-event:#{command.source_event_id}"
        ]
        markers << "target-event:#{command.target_endpoint.event_id}" if command.target_endpoint
        @event_factory.build!(
          event: Events::HistoryMigrationSourceTraceResolvedV1.new(event_attributes(command)),
          event_id: command.event_id,
          metadata: EventMetadata.new(
            command_id: command.command_id,
            actor_kind: command.actor.kind,
            actor_id: command.actor.id,
            recorded_by: "coordinator",
            policy_version: "history-migration-source-trace/v1"
          ),
          markers:,
          caused_by:
        )
      end

      def identity_from(event, command)
        payload = load(event)
        return unless identity_tuple(payload) == identity_tuple(command)

        payload.trace_id
      rescue KeyError, ArgumentError, Dry::Struct::Error
        nil
      end

      def find_identity(event, migration_id:, source_event_id:)
        payload = load(event)
        return unless payload.migration_id == migration_id && payload.source_event_id == source_event_id

        payload.trace_id
      rescue KeyError, ArgumentError, Dry::Struct::Error
        nil
      end

      def identity_tuple(value)
        [
          value.migration_id,
          value.source_event_id,
          value.source_global_position,
          value.source_causation_id,
          value.target_endpoint
        ]
      end

      def event_attributes(command)
        {
          trace_id: command.trace_id,
          migration_id: command.migration_id,
          source_event_id: command.source_event_id,
          source_global_position: command.source_global_position,
          source_causation_id: command.source_causation_id,
          target_endpoint: command.target_endpoint
        }
      end

      def trace(resolution)
        payload = load(resolution.event)
        SourceTraceV1.new(
          source_event_id: payload.source_event_id,
          source_causation_id: payload.source_causation_id,
          target_endpoint: payload.target_endpoint,
          resolution_event: resolution.event,
          outcome: resolution.outcome
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def unresolved(source_event, source_causation_id:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Source causal parent #{source_causation_id.inspect} has no resolved migration trace",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
