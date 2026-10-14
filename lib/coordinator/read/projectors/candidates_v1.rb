# frozen_string_literal: true

module Coordinator::Read::Projectors
  class CandidatesV1
    def initialize(submission_loader:, impact_surface_loader:)
      @submission_loader, @impact_surface_loader = submission_loader, impact_surface_loader
    end

    def call(events)
      owner_ids = events.select { %w[CandidateSubmitted CandidateImpactSurfaceAssigned].include?(_1.type) }
        .map { _1.data.fetch("candidate_id") }.uniq
      submissions = owner_ids.to_h { [ _1, @submission_loader.call(_1) ] }
      surfaces = events.select { _1.type == "CandidateImpactSurfaceAssigned" }.map { _1.data.fetch("surface_id") }.uniq
        .to_h { [ _1, @impact_surface_loader.call(_1) ] }
      model = Coordinator::Read::Candidate
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          headers = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :candidate_id ])
          changed = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :candidate_id, :path ])
          observed = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :candidate_id, :path ])
          keys = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :candidate_id, :direction, :impact_key ])
          fold = Coordinator::Read::Projections::Candidates.new(headers:, changed:, observed:, keys:)
          events.each do |event|
            fold.apply(event, submission: submissions[event.data.fetch("candidate_id")], surface: surfaces[event.data["surface_id"]])
          end
          [ [ model, headers ], [ Coordinator::Read::CandidateChangedResource, changed ],
            [ Coordinator::Read::CandidateObservedInput, observed ], [ Coordinator::Read::CandidateImpactKey, keys ] ].each do |table, patches|
            Coordinator::Read::Repositories::BatchWriter.new(model: table, patches:).call
          end
        end
      end
      nil
    end
  end
end
