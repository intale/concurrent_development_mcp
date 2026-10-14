# frozen_string_literal: true

module Coordinator::Read::Projectors
  class DecisionInterpretationsV1
    def initialize(source_loader:)
      @source_loader = source_loader
    end

    def call(events)
      sources = {}
      events.select { _1.type == "DecisionInterpretationProposed" }.each do |event|
        sources[event.id] ||= @source_loader.call(event)
      end
      model = Coordinator::Read::DecisionInterpretation
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          ids = events.map { _1.data.fetch("interpretation_id") }.uniq
          assessments = model.where(interpretation_id: ids).pluck(:interpretation_id, :assessment).to_h
            .transform_values { Coordinator::Read::CommandResults::Source.document(_1) }
          patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :interpretation_id ])
          fold = Coordinator::Read::Projections::DecisionInterpretations.new(patches:, sources:, assessments:)
          events.each { fold.apply(_1) }
          Coordinator::Read::Repositories::BatchWriter.new(model:, patches:).call
        end
      end
      nil
    end
  end
end
