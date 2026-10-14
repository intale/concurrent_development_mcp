# frozen_string_literal: true

module Coordinator::Read::Projectors
  class MergeSnapshotsV1
    EVENT_COLUMNS = { "MergeSnapshotVerificationSubmitted" => [ :verification_submissions ],
      "MergeSnapshotVerificationSelected" => [ :verified_decision ],
      "MergeSnapshotVerified" => %i[verification_submissions verified_decision],
      "MergeObserved" => [ :observation ], "MergeObservationAuthorizationLinked" => [ :observation ] }.freeze

    def initialize(registration_loader:)
      @registration_loader = registration_loader
    end

    def call(events)
      registrations = events.select { _1.type == "MergeSnapshotRegistered" }.uniq(&:id).to_h { [ _1.id, @registration_loader.call(_1) ] }
      model = Coordinator::Read::MergeSnapshot
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          snapshots = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :merge_snapshot_id ])
          authorizations = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :authorization_id ])
          fold = Coordinator::Read::Projections::MergeSnapshots.new(snapshots:, authorizations:, documents: load_documents(events))
          events.each { fold.apply(_1, registration: registrations[_1.id]) }
          [ [ model, snapshots ], [ Coordinator::Read::MergeAuthorization, authorizations ] ].each do |table, patches|
            Coordinator::Read::Repositories::BatchWriter.new(model: table, patches:).call
          end
        end
      end
      nil
    end

    private

    def load_documents(events)
      affected = events.select { EVENT_COLUMNS.key?(_1.type) }
      return {} if affected.empty?

      columns = affected.flat_map { EVENT_COLUMNS.fetch(_1.type) }.uniq
      ids = affected.map { _1.data.fetch("merge_snapshot_id") }.uniq
      Coordinator::Read::MergeSnapshot.where(merge_snapshot_id: ids).pluck(:merge_snapshot_id, *columns).to_h do |id, *values|
        [ id, columns.zip(values.map { Coordinator::Read::CommandResults::Source.document(_1) }).to_h ]
      end
    end
  end
end
