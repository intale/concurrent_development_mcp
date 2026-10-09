# frozen_string_literal: true

module Coordinator::Write
  class LeaseResourceLoader
    include Dry::Monads[:result]

    def initialize(
      event_store:,
      normalizer: ResourceIdentityNormalizer.new,
      schema_registry: EventSchemaRegistry.new,
      stream_factory: StreamFactory.new
    )
      @event_store = event_store
      @normalizer = normalizer
      @schema_registry = schema_registry
      @stream_factory = stream_factory
    end

    def call(target, repository_id:)
      registration_result = load_registration(target.resource_id)
      return registration_result if registration_result.failure?

      registration, identity = registration_result.value!
      return repository_mismatch(target.resource_id, registration, repository_id) unless
        registration.repository_id == repository_id

      binding_result = load_current_binding(identity, resource_id: target.resource_id)
      return binding_result if binding_result.failure?

      binding = binding_result.value!
      return inactive(target.resource_id, binding) unless
        binding.is_a?(Events::ResourceIdentityV2::Bound) && binding.resource_id == target.resource_id
      return corrupt(target.resource_id, "binding_kind_mismatch") unless binding.kind == registration.kind

      Success(
        LeaseResourceV2.new(
          resource_id: target.resource_id,
          kind: registration.kind,
          path: registration.normalized_path,
          base_blob_oid: target.base_blob_oid,
          policy_version: LeaseResourceV2::POLICY_VERSION
        )
      )
    end

    private

    def load_registration(resource_id)
      event = @event_store.read(
        @stream_factory.resource(resource_id),
        EventReadCriteria.new(
          event_types: [ "ResourceRegistered" ],
          maximum_count: 1,
          direction: :asc
        )
      ).first
      return resource_not_found(resource_id) unless event

      registration = deserialize(event)
      identity_result = @normalizer.call(
        repository_id: registration.repository_id,
        kind: registration.kind,
        path: registration.normalized_path
      )
      return corrupt(resource_id, "registration_identity_invalid") if identity_result.failure?

      identity = identity_result.value!
      return corrupt(resource_id, "registration_stream_mismatch") unless
        event.stream.stream_id == resource_id && registration.resource_id == resource_id
      return corrupt(resource_id, "registration_revision_mismatch") unless event.stream_revision.zero?
      return corrupt(resource_id, "registration_marker_mismatch") unless
        event.markers.include?(identity.identity_marker)

      canonical_event = @event_store.read_global_marked(
        GlobalMarkedEventReadCriteria.new(
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          event_types: [ "ResourceRegistered" ],
          markers: [ identity.identity_marker ],
          maximum_count: 1,
          direction: :asc
        )
      ).first
      return corrupt(resource_id, "registration_global_mismatch") unless canonical_event&.id == event.id

      Success([ registration, identity ])
    rescue EventHistoryLimitExceeded
      corrupt(resource_id, "duplicate_registration")
    rescue KeyError, Dry::Struct::Error
      corrupt(resource_id, "registration_schema_invalid")
    end

    def load_current_binding(identity, resource_id:)
      resource_stream = @stream_factory.resource(resource_id)
      event = @event_store.read_latest_global_marked(
        GlobalMarkedEventReadCriteria.new(
          stream_context: resource_stream.context,
          stream_name: resource_stream.stream_name,
          event_types: [ "ResourceBound", "ResourceUnbound" ],
          markers: [ identity.current_path_marker ],
          maximum_count: 1,
          direction: :desc
        )
      )
      return corrupt(resource_id, "binding_missing") unless event

      binding = deserialize(event)
      return corrupt(resource_id, "binding_marker_mismatch") unless
        event.markers.include?(identity.current_path_marker)
      return corrupt(resource_id, "binding_stream_mismatch") unless event.stream.stream_id == binding.resource_id
      return corrupt(resource_id, "binding_identity_mismatch") unless
        binding.repository_id == identity.repository_id &&
        binding.normalized_path == identity.normalized_path

      Success(binding)
    rescue KeyError, Dry::Struct::Error
      corrupt(resource_id, "binding_schema_invalid")
    end

    def deserialize(event)
      @schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
    end

    def resource_not_found(resource_id)
      Failure(
        OutcomeError.new(
          code: :resource_not_found,
          message: "Resource is not registered",
          details: { resource_id: }
        )
      )
    end

    def repository_mismatch(resource_id, registration, repository_id)
      Failure(
        OutcomeError.new(
          code: :resource_repository_mismatch,
          message: "Resource belongs to another repository",
          details: {
            resource_id:,
            requested_repository_id: repository_id,
            resource_repository_id: registration.repository_id
          }
        )
      )
    end

    def inactive(resource_id, binding)
      Failure(
        OutcomeError.new(
          code: :resource_not_active,
          message: "Resource is not the current binding for its repository path",
          details: {
            resource_id:,
            current_resource_id: binding.resource_id,
            current_binding: binding.class.event_type
          }
        )
      )
    end

    def corrupt(resource_id, reason)
      Failure(
        OutcomeError.new(
          code: :resource_history_corrupt,
          message: "Resource identity history is inconsistent",
          details: { resource_id:, reason: }
        )
      )
    end
  end
end
