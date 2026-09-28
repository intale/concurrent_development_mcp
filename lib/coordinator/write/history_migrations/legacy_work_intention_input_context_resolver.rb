# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyWorkIntentionInputContextResolver
      include Dry::Monads[:result]

      EXPANSION_MAXIMUM_COUNT = WorkIntentionPolicyV1::MAXIMUM_SET_SIZE - 1

      def initialize(
        event_store:,
        context_resolver:,
        post_remodel_context_resolver:,
        schema_registry: SourceEventSchemaRegistry.new
      )
        @event_store = event_store
        @context_resolver = context_resolver
        @post_remodel_context_resolver = post_remodel_context_resolver
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
        unless reservation
          return current_context(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            attempt_id:,
            lease_set_id:
          )
        end

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

      def current_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        attempt_id:,
        lease_set_id:
      )
        source_stream = StreamReference.new(
          context: "DevelopmentCoordination",
          stream_name: "WorkIntentionSet",
          stream_id: lease_set_id
        )
        root = @event_store.read_at(source_stream, 0)
        source = root && load(root)
        valid = root && root.global_position <= source_event.global_position &&
                source.is_a?(Events::WorkIntentionSetCreatedV1) &&
                source.set_id == lease_set_id && source.attempt_id == attempt_id
        return Failure(unresolved(source_event, lease_set_id:)) unless valid

        target_set = @post_remodel_context_resolver.set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_set_id: lease_set_id
        )
        return target_set if target_set.failure?

        memberships = @event_store.read(
          source_stream,
          EventReadCriteria.new(
            event_types: [ "WorkIntentionAddedToSet" ],
            maximum_count: WorkIntentionPolicyV1::MAXIMUM_SET_SIZE,
            direction: :asc
          )
        ).select { _1.global_position <= source_event.global_position }
        return Failure(unresolved(source_event, lease_set_id:)) if memberships.empty?

        members = memberships.map do |membership_event|
          current_member(
            membership_event,
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            lease_set_id:
          )
        end
        failure = members.find(&:failure?)
        return failure if failure

        values = members.map(&:value!)
        unique = values.map { [ _1.source_lease_id, _1.resource_id ] }.uniq
        return Failure(unresolved(source_event, lease_set_id:)) unless unique.length == values.length

        set = target_set.value!
        Success(
          WorkIntentionMigrationContextV1.new(
            target_set_stream: set.target_stream,
            set_id: set.set_id,
            repository_id: set.repository_id,
            change_set_id: set.change_set_id,
            work_item_id: set.work_item_id,
            attempt_id: set.attempt_id,
            repository_markers: set.repository_markers,
            members: values
          )
        )
      end

      def current_member(
        membership_event,
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        lease_set_id:
      )
        membership = load(membership_event)
        intention_stream = StreamReference.new(
          context: "DevelopmentCoordination",
          stream_name: "ResourceWorkIntention",
          stream_id: membership.intention_id
        )
        declaration_event = @event_store.read_at(intention_stream, 0)
        declaration = declaration_event && load(declaration_event)
        valid = membership.is_a?(Events::WorkIntentionAddedToSetV1) &&
                membership.set_id == lease_set_id &&
                declaration_event &&
                declaration_event.global_position <= source_event.global_position &&
                declaration.is_a?(Events::ResourceWorkIntentionDeclaredV1) &&
                declaration.set_id == lease_set_id &&
                declaration.intention_id == membership.intention_id &&
                declaration.resource_id == membership.resource_id
        return Failure(unresolved(source_event, lease_set_id:)) unless valid

        target = @post_remodel_context_resolver.intention(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_intention_id: membership.intention_id
        )
        return target if target.failure?

        intention = target.value!
        Success(
          WorkIntentionMemberMigrationV1.new(
            target_stream: intention.target_stream,
            source_lease_id: membership.intention_id,
            intention_id: intention.intention_id,
            resource_id: intention.resource_id,
            resource_kind: intention.resource_kind,
            resource_path: intention.resource_path,
            base_blob_oid: declaration.base_blob_oid,
            fencing_token: declaration.fencing_token
          )
        )
      end

      def context_for(
        event,
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        attempt_id:,
        lease_set_id:
      )
        payload = load(event)
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

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
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
