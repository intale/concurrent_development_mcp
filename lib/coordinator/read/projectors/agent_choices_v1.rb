# frozen_string_literal: true

module Coordinator::Read::Projectors
  class AgentChoicesV1
    def initialize(assessment_loader: nil)
      @assessment_loader = assessment_loader
    end

    def call(events)
      sources = {}
      invalidations = events.select { _1.type == "AgentChoiceInvalidatedByDecision" }.to_h do |event|
        id = event.markers.find { _1.start_with?("impact-assessment:") }.delete_prefix("impact-assessment:")
        [ event.id, sources.fetch(id) { sources[id] = @assessment_loader.call(id) } ]
      end
      patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :choice_id ])
      fold = Coordinator::Read::Projections::AgentChoices.new(patches:, invalidations:)
      events.each { fold.apply(_1) }
      Coordinator::Read::Repositories::BatchWriter.new(model: Coordinator::Read::AgentChoice, patches:).call
    end
  end
end
