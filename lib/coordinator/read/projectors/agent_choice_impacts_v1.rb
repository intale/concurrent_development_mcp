# frozen_string_literal: true

module Coordinator::Read::Projectors
  class AgentChoiceImpactsV1
    def initialize(assessment_loader:)
      @assessment_loader = assessment_loader
    end

    def call(events)
      ids = events.map { _1.data.fetch("assessment_id") }.uniq
      sources = ids.to_h { [ _1, @assessment_loader.call(_1) ] }
      patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :assessment_id ])
      fold = Coordinator::Read::Projections::AgentChoiceImpacts.new(patches:, sources:)
      events.each { fold.apply(_1) }
      Coordinator::Read::Repositories::BatchWriter.new(model: Coordinator::Read::AgentChoiceImpact, patches:).call
    end
  end
end
