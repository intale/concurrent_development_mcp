# frozen_string_literal: true

module Coordinator::Read::Projectors
  class ResourcesV1
    def call(events)
      patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :resource_id ])
      fold = Coordinator::Read::Projections::Resources.new(patches:)
      events.each { fold.apply(_1) }
      Coordinator::Read::Repositories::BatchWriter.new(model: Coordinator::Read::Resource, patches:).call
      nil
    end
  end
end
