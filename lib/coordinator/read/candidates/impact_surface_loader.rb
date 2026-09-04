# frozen_string_literal: true

module Coordinator::Read
  module Candidates
    class ImpactSurfaceLoader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(surface_id)
        event = @event_store.read(
          @stream_factory.candidate_impact_surface(surface_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "CandidateImpactSurfaceDerived" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Candidate impact surface is missing" unless event

        surface = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        unless surface.surface_id == surface_id && event.stream.stream_id == surface_id
          raise InvalidProjectionSource, "Candidate impact-surface identity changed"
        end

        CandidateImpactSurfaceSourceV2.new(surface:, event:)
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end
    end
  end
end
