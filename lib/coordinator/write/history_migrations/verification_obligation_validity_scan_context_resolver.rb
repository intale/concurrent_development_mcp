# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class VerificationObligationValidityScanContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        partition_reference_resolver:,
        target_event_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @partition_reference_resolver = partition_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @schema_registry = schema_registry
      end

      def from_started(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_started:
      )
        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          started_event: source_event,
          source_started:,
          include_target_reference: false
        )
      end

      def from_stream(migration_id:, source_config_name:, source_upper_position:, source_event:)
        started_event = @event_store.read_at(stream_for(source_event), 0)
        unless started_event && started_event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "scan start is absent from the frozen source range"))
        end

        source_started = load(started_event)
        unless source_started.is_a?(Events::VerificationObligationValidityScanStartedV1)
          return Failure(inconsistent(source_event, "scan stream does not begin with the V1 start fact"))
        end

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          started_event:,
          source_started:,
          include_target_reference: true
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        event = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        unless event && event.id == source_reference.event_id && event.type == source_reference.type &&
            event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "scan checkpoint is absent from the frozen source range"))
        end

        Success([ event, load(event) ].freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def target_reference(
        migration_id:,
        source_upper_position:,
        source_event:,
        source_reference:,
        target_stream:,
        target_event_type:,
        target_step_name:
      )
        @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream:,
          target_event_type:,
          target_step_name:
        )
      end

      private

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        started_event:,
        source_started:,
        include_target_reference:
      )
        physical = validate_started(
          source_event:,
          started_event:,
          source_started:,
          source_upper_position:
        )
        return physical if physical.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: started_event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "VerificationObligationValidityScan",
          identity_role: "verification-obligation-validity-scan"
        )
        return allocation if allocation.failure?

        change_set = @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "ChangeSet",
            stream_id: source_started.change_set_id
          ),
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        partition = @partition_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source_started.superseding_partition_event
        )
        return partition if partition.failure?

        target_stream = allocation.value!.target_stream
        target_started_event = if include_target_reference
          mapped = target_reference(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: reference_for(started_event),
            target_stream:,
            target_event_type: "VerificationObligationValidityScanStarted",
            target_step_name: "start-verification-obligation-validity-scan"
          )
          return mapped if mapped.failure?

          mapped.value!
        end

        Success(
          VerificationObligationValidityScanContextV1.new(
            source_started:,
            source_started_event: started_event,
            target_started_event:,
            target_stream:,
            scan_id: target_stream.stream_id,
            change_set_id: change_set.value!.target_stream.stream_id,
            superseding_partition_event: partition.value!.first
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def validate_started(source_event:, started_event:, source_started:, source_upper_position:)
        stream = stream_for(started_event)
        valid = started_event.type == "VerificationObligationValidityScanStarted" &&
                started_event.metadata.fetch("schema_version") == 1 &&
                started_event.global_position <= source_upper_position &&
                started_event.stream_revision.zero? &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "VerificationObligationValidityScan" &&
                stream.stream_id == source_started.scan_id &&
                started_event.markers.include?("verification-obligation-validity-scan:#{source_started.scan_id}")
        return Success() if valid

        Failure(inconsistent(source_event, "scan identity, schema, stream, revision, or marker is invalid"))
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(value)
        stream = value.respond_to?(:stream) ? value.stream : value
        StreamReference.new(
          context: stream.respond_to?(:context) ? stream.context : stream.stream_context,
          stream_name: stream.stream_name,
          stream_id: stream.stream_id
        )
      end

      def reference_for(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Verification-obligation validity scan migration is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
