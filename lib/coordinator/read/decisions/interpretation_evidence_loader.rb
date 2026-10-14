# frozen_string_literal: true

module Coordinator::Read::Decisions
  class InterpretationEvidenceLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(interpretation_id)
      events = @event_store.read(@stream_factory.interpretation(interpretation_id), Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionInterpretationProposed DecisionInterpretationAccepted], maximum_count: 2, direction: :asc))
      proposal = events.find { _1.type == "DecisionInterpretationProposed" }
      acceptance = events.find { _1.type == "DecisionInterpretationAccepted" }
      source = @event_store.read_global_marked(
        Coordinator::Write::EventQueries.guidance_message("message:#{proposal.data.fetch('source_message_id')}")).first
      { source_event: Coordinator::Read::Projections::Source.reference(source),
        proposal_event: Coordinator::Read::Projections::Source.reference(proposal),
        acceptance_event: Coordinator::Read::Projections::Source.reference(acceptance),
        classifier: Coordinator::Read::CommandResults::Source.document(proposal.metadata.fetch("classifier")),
        scope_provenance: Coordinator::Read::CommandResults::Source.document(proposal.metadata.fetch("scope_provenance")) }
    end
  end
end
