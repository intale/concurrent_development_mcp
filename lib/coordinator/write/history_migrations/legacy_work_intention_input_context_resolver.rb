# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyWorkIntentionInputContextResolver
      include Dry::Monads[:result]

      EXPANSION_MAXIMUM_COUNT = WorkIntentionPolicyV1::MAXIMUM_SET_SIZE - 1

      def initialize(
        event_store:,
        context_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @context_resolver = context_resolver
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        attempt_id:,
        lease_set_id:
      )
        reservation = @event_store.read_marked(
          StreamReference.new(
            context: "DevelopmentExecution",
            stream_name: "Attempt",
            stream_id: attempt_id
          ),
          MarkedEventReadCriteria.new(
            event_type: "WriteSetReserved",
            marker: "lease-set:#{lease_set_id}",
            maximum_count: 1,
            direction: :asc
          )
        ).find { _1.global_position <= source_event.global_position }
        return Failure(unresolved(source_event, lease_set_id:)) unless reservation

        expansions = @event_store.read_marked(
          StreamReference.new(
            context: "DevelopmentExecution",
            stream_name: "Attempt",
            stream_id: attempt_id
          ),
          MarkedEventReadCriteria.new(
            event_type: "WriteSetExpanded",
            marker: "lease-set:#{lease_set_id}",
            maximum_count: EXPANSION_MAXIMUM_COUNT,
            direction: :asc
          )
        ).select { _1.global_position <= source_event.global_position }
        contexts = [ reservation, *expansions ].map do |event|
          context_for(
            event,
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            attempt_id:,
            lease_set_id:
          )
        end
        failure = contexts.find(&:failure?)
        return failure if failure

        merge_contexts(contexts.map(&:value!), source_event:, lease_set_id:)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded
        Failure(unresolved(source_event, lease_set_id:))
      end

      private

      def context_for(
        event,
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        attempt_id:,
        lease_set_id:
      )
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        unless (payload.is_a?(Events::WriteSetReservedV2) ||
                payload.is_a?(Events::WriteSetExpandedV2)) &&
            payload.attempt_id == attempt_id && payload.lease_set_id == lease_set_id
          return Failure(unresolved(source_event, lease_set_id:))
        end

        @context_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event: event,
          source_payload: payload
        )
      end

      def merge_contexts(contexts, source_event:, lease_set_id:)
        base = contexts.first
        comparable = %i[
          target_set_stream
          set_id
          repository_id
          change_set_id
          work_item_id
          attempt_id
          repository_markers
        ]
        unless contexts.all? { |context| comparable.all? { context.public_send(_1) == base.public_send(_1) } }
          return Failure(unresolved(source_event, lease_set_id:))
        end

        members = contexts.flat_map(&:members)
        unique = members.map { [ _1.intention_id, _1.resource_id ] }.uniq
        return Failure(unresolved(source_event, lease_set_id:)) unless unique.length == members.length

        Success(WorkIntentionMigrationContextV1.new(base.to_h.merge(members:)))
      end

      def unresolved(source_event, lease_set_id:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Legacy work-intention set #{lease_set_id.inspect} is absent or inconsistent",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
