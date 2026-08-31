# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactSummaryType < BaseObject
    graphql_name "DevelopmentArtifactSummary"

    field :byte_size, Integer, null: false
    field :captured_at, String, null: false
    field :classification_reason, String, null: true
    field :classification_revision, Integer, null: false
    field :classified_at, String, null: false
    field :content_digest, String, null: false, method: :content_sha256
    field :encoding, String, null: false
    field :id, ID, null: false, method: :artifact_id
    field :kind, DevelopmentArtifactKindEnum, null: false
    field :labels, [ String ], null: false
    field :media_type, String, null: false
    field :observation_id, ID, null: false
    field :observed_at, String, null: false
    field :relationship_count, Integer, null: false
    field :scope, String, null: false
    field :source, DevelopmentArtifactSourceType, null: false
    field :title, String, null: false

    def captured_at
      object.captured.occurred_at
    end

    def classified_at
      object.classified.occurred_at
    end

    def observed_at
      object.observed.occurred_at
    end
  end
end
