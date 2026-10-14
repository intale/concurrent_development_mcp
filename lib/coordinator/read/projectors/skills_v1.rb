# frozen_string_literal: true

module Coordinator::Read::Projectors
  class SkillsV1
    def initialize(publication_loader:)
      @publication_loader = publication_loader
    end

    def call(events)
      latest = events.to_h { [ _1.data.fetch("skill_id"), _1 ] }
      sources = latest.values.map { @publication_loader.call(_1) }
      return if sources.empty?

      models = [ Coordinator::Read::Skill, Coordinator::Read::SkillRevision, Coordinator::Read::SkillAsset ]
      models.first.connection_pool.with_connection do |connection|
        connection.transaction do
          pairs = sources.map { [ _1.fetch(:skill_id), _1.fetch(:revision) ] }
          models.drop(1).each do |model|
            model.where(skill_id: latest.keys).where.not([ :skill_id, :revision ] => pairs).delete_all
          end
          heads = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :skill_id ])
          revisions = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :skill_id, :revision ])
          assets = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :skill_id, :revision, :path ])
          fold = Coordinator::Read::Projections::Skills.new(heads:, revisions:, assets:)
          sources.each { fold.apply(_1) }
          models.zip([ heads, revisions, assets ]).each do |model, patches|
            Coordinator::Read::Repositories::BatchWriter.new(model:, patches:).call
          end
        end
      end
      nil
    end
  end
end
