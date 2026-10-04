# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelRepositoryTransformer
      include Dry::Monads[:result]

      def initialize(event_store:, stream_identity_allocator:, natural_key_marker: Repositories::NaturalKeyMarker.new)
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @natural_key_marker = natural_key_marker
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        registration_event = @event_store.read_at(
          StreamReference.new(context: source_event.stream.context, stream_name: "Repository", stream_id: source_event.stream.stream_id), 0
        )
        unless source_payload.repository_id == source_event.stream.stream_id &&
               registration_event && registration_event.type == "RepositoryRegistered" && registration_event.global_position <= source_upper_position
          return Failure(TransformationErrorV1.new(
            code: :ambiguous_source_reference, message: "Repository registration is absent from the frozen range",
            event_type: source_event.type, schema_version: source_event.metadata["schema_version"], source_event_id: source_event.id
          ))
        end

        allocation = @stream_identity_allocator.call(
          migration_id:, source_config_name:, source_event: registration_event,
          target_stream_context: "DevelopmentPlanning", target_stream_name: "Repository", identity_role: "repository"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        payload = source_payload.class.new(source_payload.to_h.merge(repository_id: target_stream.stream_id))
        markers = [ "repository:#{target_stream.stream_id}", "repository-key:#{registration_event.data.fetch('repository_key')}" ]
        if payload.is_a?(Events::RepositoryRegisteredV2)
          markers << @natural_key_marker.call(scope: payload.scope, repository_key: payload.repository_key).marker
        end
        Success([ TransformedFactV1.new(
          target_stream:, event: payload, markers:, step_name: "migrate-repository-fact"
        ) ])
      end
    end
  end
end
