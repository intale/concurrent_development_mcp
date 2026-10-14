# frozen_string_literal: true

module Coordinator::Read::Projections
  class Skills
    def initialize(heads:, revisions:, assets:)
      @heads, @revisions, @assets = heads, revisions, assets
    end

    def apply(source)
      event = source.fetch(:published_event)
      id, revision = source.fetch(:skill_id), source.fetch(:revision)
      head = { skill_id: id, name: source.fetch(:name), scope: source.fetch(:scope), revision: }
      @heads.insert(head.merge(created_at: source.fetch(:registered_at), updated_at: event.created_at))
      @heads.assign(head)
      @heads.touch({ skill_id: id }, time: event.created_at)
      snapshot = { skill_id: id, revision:, description: source.fetch(:description), instructions: source.fetch(:instructions),
        content_digest: source.fetch(:content_digest), asset_count: source.fetch(:asset_count) }
        .merge(Source.evidence(event, prefix: :published))
      @revisions.insert(snapshot.merge(created_at: event.created_at, updated_at: event.created_at))
      @revisions.assign(snapshot)
      @revisions.touch({ skill_id: id, revision: }, time: event.created_at)
      source.fetch(:assets).each do |asset|
        attributes = asset.merge(skill_id: id, revision:)
        @assets.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
        @assets.assign(attributes)
        @assets.touch({ skill_id: id, revision:, path: asset.fetch(:path) }, time: event.created_at)
      end
      nil
    end
  end
end
