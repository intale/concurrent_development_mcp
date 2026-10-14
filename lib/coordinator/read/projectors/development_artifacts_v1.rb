# frozen_string_literal: true

module Coordinator::Read::Projectors
  class DevelopmentArtifactsV1
    LABEL_TYPES = %w[DevelopmentArtifactLabelAdded DevelopmentArtifactLabelRemoved].freeze

    def initialize(event_store:, fact_loader: Coordinator::Read::DevelopmentArtifacts::ObservationFactLoader.new(event_store:))
      @fact_loader = fact_loader
    end

    def call(events)
      facts = linked_facts(events)
      model = Coordinator::Read::DevelopmentArtifact
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          patches = {
            artifacts: Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :artifact_id ]),
            observations: Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :observation_id ]),
            links: Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :link_event_id ]),
            relations: Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :relation_id ]),
            supersessions: Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :superseded_relation_id ])
          }
          artifact_ids = events.select { LABEL_TYPES.include?(_1.type) }.map { _1.data.fetch("artifact_id") }.uniq
          observation_ids = events.select { facts[_1.id] && LABEL_TYPES.include?(facts.fetch(_1.id).type) }.map { _1.data.fetch("observation_id") }.uniq
          fold = Coordinator::Read::Projections::DevelopmentArtifacts.new(**patches,
            artifact_labels: labels(model, :artifact_id, artifact_ids),
            observation_labels: labels(Coordinator::Read::DevelopmentArtifactObservation, :observation_id, observation_ids))
          events.each { fold.apply(_1, observed_fact: facts[_1.id]) }
          tables = [ model, Coordinator::Read::DevelopmentArtifactObservation, Coordinator::Read::DevelopmentArtifactObservationFactLink,
            Coordinator::Read::DevelopmentArtifactRelation, Coordinator::Read::DevelopmentArtifactRelationSupersession ]
          tables.zip(patches.values).each { |table, changes| Coordinator::Read::Repositories::BatchWriter.new(model: table, patches: changes).call }
        end
      end
      nil
    end

    private

    def linked_facts(events)
      cache = {}
      events.select { _1.type == "DevelopmentArtifactObservationFactLinked" }.to_h do |event|
        reference = Coordinator::Read::CommandResults::Source.document(event.data.fetch("observed_fact"))
        key = reference.values_at(:stream_context, :stream_name, :stream_id, :stream_revision)
        [ event.id, cache[key] ||= @fact_loader.call(reference) ]
      end
    end

    def labels(model, column, ids)
      ids.empty? ? {} : model.where(column => ids).pluck(column, :labels).to_h
    end
  end
end
