# frozen_string_literal: true

module Coordinator::Read::Interpretations
  # Immutable proposal provenance is enriched without revalidating stored facts.
  class ProjectionSourceLoader
    def initialize(event_store:)
      @event_store = event_store
    end

    def call(event)
      data = event.data
      source = @event_store.read_global_marked(
        Coordinator::Write::EventQueries.guidance_message("message:#{data.fetch('source_message_id')}")
      ).first
      selected = data.fetch("source_span")
      start = source.data.fetch("text").index(selected)
      {
        source_event: Coordinator::Read::Projections::Source.reference(source),
        source_span: { start_character: start, end_character: start + selected.length, text: selected },
        classifier: Coordinator::Read::CommandResults::Source.document(event.metadata.fetch("classifier")),
        scope_provenance: Coordinator::Read::CommandResults::Source.document(event.metadata.fetch("scope_provenance")),
        ambiguities: data.fetch("ambiguities").map.with_index do |description, index|
          { field: "unspecified_#{index + 1}", code: "reported_ambiguity", description:, options: [] }
        end
      }
    end
  end
end
