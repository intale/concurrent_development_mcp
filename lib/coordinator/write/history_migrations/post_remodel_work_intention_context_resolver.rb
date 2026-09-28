# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelWorkIntentionContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        repository_marker_builder: RepositoryMarkerBuilder.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @repository_marker_builder = repository_marker_builder
        @schema_registry = schema_registry
      end

      def set(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_set_id:
      )
        source_stream = StreamReference.new(
          context: "DevelopmentCoordination",
          stream_name: "WorkIntentionSet",
          stream_id: source_set_id
        )
        root = @event_store.read_at(source_stream, 0)
        source = root && load(root)
        valid = root && root.global_position <= source_upper_position &&
                source.is_a?(Events::WorkIntentionSetCreatedV1) &&
                source.set_id == source_set_id
        return Failure(invalid(source_event, "work-intention set root is absent or inconsistent")) unless valid

        set = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: root,
          target_stream_context: "DevelopmentCoordination",
          target_stream_name: "WorkIntentionSet",
          identity_role: "work-intention-set"
        )
        return set if set.failure?

        repository = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "Repository",
          source_id: source.repository_id,
          target_context: "DevelopmentPlanning",
          target_name: "Repository",
          identity_role: "repository"
        )
        return repository if repository.failure?

        change_set = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id: source.change_set_id,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        work_item = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "WorkItem",
          source_id: source.work_item_id,
          target_context: "DevelopmentExecution",
          target_name: "WorkItem",
          identity_role: "work-item"
        )
        return work_item if work_item.failure?

        attempt = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "Attempt",
          source_id: source.attempt_id,
          target_context: "DevelopmentExecution",
          target_name: "Attempt",
          identity_role: "attempt"
        )
        return attempt if attempt.failure?

        repository_id = repository.value!.target_stream.stream_id
        Success(
          PostRemodelWorkIntentionSetContextV1.new(
            target_stream: set.value!.target_stream,
            set_id: set.value!.target_stream.stream_id,
            repository_id:,
            change_set_id: change_set.value!.target_stream.stream_id,
            work_item_id: work_item.value!.target_stream.stream_id,
            attempt_id: attempt.value!.target_stream.stream_id,
            repository_markers: repository_markers(
              source.repository_id,
              target_repository_id: repository_id,
              source_upper_position:
            )
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      def intention(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_intention_id:
      )
        source_stream = StreamReference.new(
          context: "DevelopmentCoordination",
          stream_name: "ResourceWorkIntention",
          stream_id: source_intention_id
        )
        root = @event_store.read_at(source_stream, 0)
        source = root && load(root)
        valid = root && root.global_position <= source_upper_position &&
                source.is_a?(Events::ResourceWorkIntentionDeclaredV1) &&
                source.intention_id == source_intention_id
        return Failure(invalid(source_event, "work-intention root is absent or inconsistent")) unless valid

        intention = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: root,
          target_stream_context: "DevelopmentCoordination",
          target_stream_name: "ResourceWorkIntention",
          identity_role: "work-intention"
        )
        return intention if intention.failure?

        set = set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_set_id: source.set_id
        )
        return set if set.failure?

        resource = resource(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_resource_id: source.resource_id
        )
        return resource if resource.failure?

        resource_id, resource_kind, resource_path = resource.value!
        Success(
          PostRemodelWorkIntentionContextV1.new(
            target_stream: intention.value!.target_stream,
            intention_id: intention.value!.target_stream.stream_id,
            set: set.value!,
            resource_id:,
            resource_kind:,
            resource_path:
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      def resource(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_resource_id:
      )
        stream = StreamReference.new(
          context: "DevelopmentCoordination",
          stream_name: "Resource",
          stream_id: source_resource_id
        )
        root = @event_store.read_at(stream, 0)
        registration = root && load(root)
        valid = root && root.global_position <= source_upper_position &&
                registration.is_a?(Events::ResourceIdentityV1::Registered) &&
                registration.resource_id == source_resource_id
        return Failure(invalid(source_event, "Resource root is absent or inconsistent")) unless valid

        migrated = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: stream.context,
          source_name: stream.stream_name,
          source_id: stream.stream_id,
          target_context: stream.context,
          target_name: stream.stream_name,
          identity_role: "resource"
        )
        return migrated if migrated.failure?

        Success([
          migrated.value!.target_stream.stream_id,
          registration.kind,
          registration.normalized_path
        ])
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      private

      def repository_markers(source_repository_id, target_repository_id:, source_upper_position:)
        event = @event_store.read_at(
          StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "Repository",
            stream_id: source_repository_id
          ),
          0
        )
        source = event && load(event)
        valid = event && event.global_position <= source_upper_position &&
                source.is_a?(Events::RepositoryRegisteredV1) &&
                source.repository_id == source_repository_id
        raise ArgumentError, "Repository registration is absent or inconsistent" unless valid

        @repository_marker_builder.call(
          RepositoryRegistrationV2.new(
            repository_id: target_repository_id,
            scope: source.scope,
            repository_key: source.repository_key,
            display_name: nil,
            paths: [],
            remotes: []
          )
        )
      end

      def resolve_entity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_context:,
        source_name:,
        source_id:,
        target_context:,
        target_name:,
        identity_role:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: source_context,
            stream_name: source_name,
            stream_id: source_id
          ),
          target_stream_context: target_context,
          target_stream_name: target_name,
          identity_role:
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel WorkIntention context is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
