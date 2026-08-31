# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class SkillSummaryType < BaseObject
    graphql_name "SkillSummary"

    field :asset_count, Integer, null: false
    field :content_digest, String, null: false
    field :description, String, null: false
    field :id, ID, null: false, method: :skill_id
    field :name, String, null: false
    field :published_at, String, null: false
    field :revision, Integer, null: false
    field :scope, String, null: false

    def published_at
      object.published.occurred_at
    end
  end
end
