# frozen_string_literal: true

module Coordinator::Read::Projectors
  class ReleaseSetsV1
    EVENT_COLUMNS = {
      "RepositoryIntegrationRecorded" => :integrations, "RepositoryIntegrationMergeLinked" => :integrations,
      "ReleaseSetVerificationRecorded" => :verifications, "ReleaseSetIntegrationLinked" => :verifications,
      "ReleaseSetActivated" => :verifications, "ReleaseSetCompensationRequested" => :compensation_request,
      "ReleaseSetSuccessfulIntegrationLinked" => :compensation_request,
      "RepositoryCompensationRecorded" => :completion, "ReleaseSetOutcomeRecorded" => :completion, "ReleaseSetCompleted" => :completion
    }.freeze

    def initialize(preparation_loader:)
      @preparation_loader = preparation_loader
    end

    def call(events)
      preparations = events.select { _1.type == "ReleaseSetPrepared" }.uniq { [ _1.data.fetch("release_set_id"), _1.stream_revision ] }
        .to_h do |event|
          id = event.data.fetch("release_set_id")
          [ [ id, event.stream_revision ], @preparation_loader.call(id, through_revision: event.stream_revision) ]
        end
      model = Coordinator::Read::ReleaseSet
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          documents = load_documents(events)
          patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :release_set_id ])
          fold = Coordinator::Read::Projections::ReleaseSets.new(patches:, documents:)
          events.each do |event|
            preparation = preparations[[ event.data.fetch("release_set_id"), event.stream_revision ]]
            fold.apply(event, preparation:)
          end
          Coordinator::Read::Repositories::BatchWriter.new(model:, patches:).call
        end
      end
      nil
    end

    private

    def load_documents(events)
      affected = events.select { EVENT_COLUMNS.key?(_1.type) }
      return {} if affected.empty?

      columns = affected.map { EVENT_COLUMNS.fetch(_1.type) }.uniq
      ids = affected.map { _1.data.fetch("release_set_id") }.uniq
      Coordinator::Read::ReleaseSet.where(release_set_id: ids).pluck(:release_set_id, *columns).to_h do |id, *values|
        [ id, columns.zip(values.map { Coordinator::Read::CommandResults::Source.document(_1) }).to_h ]
      end
    end
  end
end
