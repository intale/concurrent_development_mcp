# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class SkillType < BaseObject
    graphql_name "Skill"

    field :assets, [ SkillAssetManifestType ], null: false
    field :content_digest, String, null: false
    field :description, String, null: false
    field :id, ID, null: false, method: :skill_id
    field :instructions, String, null: false
    field :name, String, null: false
    field :published_at, String, null: false
    field :revision, Integer, null: false
    field :scope, String, null: false

    def published_at
      object.published.occurred_at
    end
  end
end
