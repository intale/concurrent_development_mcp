# frozen_string_literal: true

module Coordinator::Read::Projectors
  class RepositoriesV1
    def call(events)
      ApplicationRecord.transaction do
        patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :repository_id ])
        collections = collection_state(events)
        fold = Coordinator::Read::Projections::Repositories.new(patches:, **collections)
        events.each { fold.apply(_1) }
        Coordinator::Read::Repositories::BatchWriter.new(model: Coordinator::Read::Repository, patches:).call
      end
      nil
    end

    private

    def collection_state(events)
      columns = []
      columns << :paths if events.any? { %w[RepositoryPathAdded RepositoryPathRemoved].include?(_1.type) }
      columns << :remotes if events.any? { %w[RepositoryRemoteAdded RepositoryRemoteRemoved].include?(_1.type) }
      return {} if columns.empty?

      ids = events.map { _1.data.fetch("repository_id") }.uniq
      rows = Coordinator::Read::Repository.where(repository_id: ids).pluck(:repository_id, *columns)
      columns.map.with_index do |column, index|
        [ column, rows.to_h { [ _1.first, _1.fetch(index + 1) ] } ]
      end.to_h
    end
  end
end
