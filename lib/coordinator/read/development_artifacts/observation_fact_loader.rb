# frozen_string_literal: true

module Coordinator::Read::DevelopmentArtifacts
  class ObservationFactLoader
    def initialize(event_store:)
      @event_store = event_store
    end

    def call(reference)
      @event_store.read_at(Coordinator::Write::StreamReference.new(
        context: reference.fetch(:stream_context), stream_name: reference.fetch(:stream_name), stream_id: reference.fetch(:stream_id)),
        reference.fetch(:stream_revision))
    end
  end
end
