# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class ResourceV1Transformer
      include Dry::Monads[:result]

      SOURCE_CLASSES = {
        "ResourceRegistered" => Events::ResourceIdentityV1::Registered,
        "ResourceBound" => Events::ResourceIdentityV1::Bound,
        "ResourceUnbound" => Events::ResourceIdentityV1::Unbound
      }.freeze

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        normalizer: ResourceIdentityNormalizer.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @normalizer = normalizer
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        registration_event, registration = source_registration(
          source_event,
          source_upper_position:
        )
        validate_source!(
          source_event,
          source_payload,
          registration_event:,
          registration:,
          source_upper_position:
        )

        resource = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: registration_event,
          target_stream_context: "DevelopmentCoordination",
          target_stream_name: "Resource",
          identity_role: "resource"
        )
        return resource if resource.failure?

        repository = @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "Repository",
            stream_id: registration.repository_id
          ),
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "Repository",
          identity_role: "repository"
        )
        return repository if repository.failure?

        target_stream = resource.value!.target_stream
        resource_id = target_stream.stream_id
        repository_id = repository.value!.target_stream.stream_id
        identity = normalized_identity(
          repository_id:,
          kind: registration.kind,
          path: registration.normalized_path
        )
        target_event = target_event(
          source_payload,
          resource_id:,
          repository_id:,
          normalized_path: identity.normalized_path
        )
        Success([
          TransformedFactV1.new(
            target_stream:,
            event: target_event,
            markers: markers(target_event, identity:),
            step_name: step_name(target_event),
            metadata_extension: actor_metadata(source_event)
          )
        ])
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def source_registration(source_event, source_upper_position:)
        stream = stream_for(source_event)
        event = @event_store.read_at(stream, 0)
        payload = event && load(event)
        valid = event &&
                event.global_position <= source_upper_position &&
                payload.is_a?(Events::ResourceIdentityV1::Registered)
        raise ArgumentError, "Resource registration is absent from the frozen source range" unless valid

        [ event, payload ]
      end

      def validate_source!(
        source_event,
        source,
        registration_event:,
        registration:,
        source_upper_position:
      )
        expected_class = SOURCE_CLASSES.fetch(source_event.type)
        persisted = @event_store.read_at(stream_for(source_event), source_event.stream_revision)
        valid = source.is_a?(expected_class) &&
                persisted&.id == source_event.id &&
                source_event.metadata.fetch("schema_version") == expected_class.schema_version &&
                source_event.global_position <= source_upper_position &&
                source_event.stream.context == "DevelopmentCoordination" &&
                source_event.stream.stream_name == "Resource" &&
                source_event.stream.stream_id == registration.resource_id &&
                source.resource_id == registration.resource_id &&
                source.repository_id == registration.repository_id &&
                source.kind == registration.kind &&
                source.normalized_path == registration.normalized_path &&
                registration_event.stream_revision.zero?
        raise ArgumentError, "Resource source identity, schema, or stream is inconsistent" unless valid

        identity = normalized_identity(
          repository_id: source.repository_id,
          kind: source.kind,
          path: source.normalized_path
        )
        required_markers = [
          identity.identity_marker,
          "resource:#{source.resource_id}",
          "repository:#{source.repository_id}"
        ]
        if source.is_a?(Events::ResourceIdentityV1::Bound) ||
           source.is_a?(Events::ResourceIdentityV1::Unbound)
          required_markers << identity.current_path_marker
        end
        unless (required_markers - source_event.markers).empty?
          raise ArgumentError, "Resource source markers are inconsistent"
        end
      end

      def normalized_identity(repository_id:, kind:, path:)
        result = @normalizer.call(repository_id:, kind:, path:)
        raise ArgumentError, result.failure.message if result.failure?

        result.value!
      end

      def target_event(source, resource_id:, repository_id:, normalized_path:)
        common = {
          resource_id:,
          repository_id:,
          kind: source.kind,
          normalized_path:
        }
        case source
        when Events::ResourceIdentityV1::Registered
          Events::ResourceIdentityV2::Registered.new(**common)
        when Events::ResourceIdentityV1::Bound
          Events::ResourceIdentityV2::Bound.new(**common)
        when Events::ResourceIdentityV1::Unbound
          Events::ResourceIdentityV2::Unbound.new(**common, reason: source.reason)
        end
      end

      def markers(event, identity:)
        values = [
          identity.identity_marker,
          "resource:#{event.resource_id}",
          "repository:#{event.repository_id}"
        ]
        if event.is_a?(Events::ResourceIdentityV2::Bound) ||
           event.is_a?(Events::ResourceIdentityV2::Unbound)
          values << identity.current_path_marker
        end
        values
      end

      def step_name(event)
        case event
        when Events::ResourceIdentityV2::Registered then "register-resource"
        when Events::ResourceIdentityV2::Bound then "bind-resource"
        when Events::ResourceIdentityV2::Unbound then "unbind-resource"
        end
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def load(event)
        EventSchemaRegistry.new.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def actor_metadata(source_event)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version: source_event.metadata.fetch("policy_version")
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Resource transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
