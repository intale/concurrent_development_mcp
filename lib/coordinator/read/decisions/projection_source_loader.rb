# frozen_string_literal: true

module Coordinator::Read::Decisions
  class ProjectionSourceLoader
    def initialize(event_store:, interpretation_loader: InterpretationEvidenceLoader.new(event_store:),
      stream_factory: Coordinator::Write::StreamFactory.new, canonical_json: Coordinator::Shared::CanonicalJson.new)
      @event_store, @interpretation_loader, @stream_factory, @canonical_json = event_store, interpretation_loader, stream_factory, canonical_json
    end

    def call(event)
      data = event.data
      case event.type
      when "DecisionRecorded", "DecisionDefinitionCorrected"
        source = { interpretation: @interpretation_loader.call(data.fetch("interpretation_id")),
          definition: definition(data.fetch("definition")) }
        if event.type == "DecisionDefinitionCorrected"
          previous = definition_event(data.fetch("decision_id"), through_revision: event.stream_revision - 1)
          source[:previous_definition_digest] = definition(previous.data.fetch("definition")).fetch(:digest)
        end
        source
      when "DecisionActivated"
        fact = definition_event(data.fetch("decision_id"), through_revision: event.stream_revision)
        { definition: definition(fact.data.fetch("definition")) }
      when "DecisionAddedToPartition", "DecisionRemovedFromPartition"
        head = @event_store.read_latest_global_marked(Coordinator::Write::GlobalMarkedEventReadCriteria.new(
          stream_context: "HumanGuidance", stream_name: "Decision", event_types: %w[DecisionActivated DecisionDefinitionCorrected],
          markers: [ "decision:#{data.fetch('decision_id')}" ], maximum_count: 1, direction: :desc, from_position: event.global_position))
        { head: { decision_id: data.fetch("decision_id"), decision_revision: head.stream_revision,
          event: Coordinator::Read::Projections::Source.reference(head) },
          change_kind: head.type == "DecisionDefinitionCorrected" ? "corrected" : "activated" }
      else {}
      end
    end

    private

    def definition_event(id, through_revision:)
      @event_store.read_latest(@stream_factory.decision(id), Coordinator::Write::LatestEventReadCriteria.new(
        event_types: %w[DecisionRecorded DecisionDefinitionCorrected], from_revision: through_revision))
    end

    def definition(document)
      { document: Coordinator::Read::CommandResults::Source.document(document), digest: @canonical_json.sha256(document) }
    end
  end
end
