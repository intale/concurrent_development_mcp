# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactRelationType < BaseObject
    graphql_name "DevelopmentArtifactRelation"

    field :declared_at, String, null: false
    field :direction, ArtifactRelationDirectionEnum, null: false
    field :display_relation, String, null: false
    field :fragment, String, null: true
    field :id, ID, null: false, method: :relation_id
    field :normalized_locator, String, null: true
    field :path, String, null: true
    field :peer_artifact, DevelopmentArtifactSummaryType, null: true
    field :peer_id, ID, null: false
    field :peer_kind, String, null: false
    field :relation, DevelopmentArtifactRelationKindEnum, null: false
    field :status, String, null: false
    field :target_name, String, null: true
    field :target_scope, String, null: true
    field :target_status, String, null: false

    def declared_at
      object.declared.occurred_at
    end

    def fragment
      object.relation_attributes.fragment
    end

    def normalized_locator
      object.relation_attributes.normalized_locator
    end

    def path
      object.relation_attributes.path
    end

    def target_name
      object.target.name
    end

    def target_scope
      object.target.scope
    end

    def target_status
      object.target.status
    end
  end
end
