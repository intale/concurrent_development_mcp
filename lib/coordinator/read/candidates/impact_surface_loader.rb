# frozen_string_literal: true

module Coordinator::Read::Candidates
  class ImpactSurfaceLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(surface_id)
      event = @event_store.read(@stream_factory.candidate_impact_surface(surface_id), Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceDerived" ], maximum_count: 1, direction: :asc)).first
      Coordinator::Read::CandidateImpactSurfaceSourceV2.new(
        surface: Coordinator::Read::CommandResults::Source.document(event.data), event:)
    end
  end
end
