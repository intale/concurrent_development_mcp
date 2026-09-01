# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class KnowledgeBrowser
    def initialize(
      skills: Coordinator::Read::Repositories::Skills.new,
      artifacts: Coordinator::Read::Repositories::DevelopmentArtifacts.new
    )
      @skills = skills
      @artifacts = artifacts
    end

    def skills(query)
      return unless project_exists?(query.scope)

      @skills.page(
        Coordinator::Read::SkillListQueryV1.new(
          name: query.name,
          scope: query.scope,
          after_skill_id: query.after_skill_id,
          limit: query.first
        )
      )
    end

    def artifacts(query)
      return unless project_exists?(query.scope)

      @artifacts.page(
        Coordinator::Read::DevelopmentArtifactListQueryV1.new(
          scope: query.scope,
          kind: query.kind,
          labels: query.labels,
          source_kind: query.source_kind,
          relation_target_kind: nil,
          relation_target_id: nil,
          after_global_position: query.after_global_position,
          limit: query.first
        )
      )
    end

    def skill(query)
      return unless project_exists?(query.scope)

      skill = @skills.fetch(name: query.name, scope: query.scope)
      skill && Coordinator::Read::Web::KnowledgeBrowserV1::SkillDetail.new(skill:)
    end

    def skill_asset(query)
      return unless project_exists?(query.scope)

      asset = @skills.fetch_asset(name: query.name, scope: query.scope, path: query.path)
      asset && Coordinator::Read::Web::KnowledgeBrowserV1::SkillAssetDetail.new(asset:)
    end

    def artifact(query)
      artifact = project_artifact(query.scope, query.artifact_id)
      return unless artifact

      Coordinator::Read::Web::KnowledgeBrowserV1::ArtifactDetail.new(
        artifact:,
        content: @artifacts.fetch_content(query.artifact_id)
      )
    end

    def relationships(query)
      artifact = project_artifact(query.scope, query.artifact_id)
      return unless artifact

      Coordinator::Read::Web::KnowledgeBrowserV1::ArtifactRelationships.new(
        artifact:,
        relationships: @artifacts.relation_page(
          Coordinator::Read::DevelopmentArtifactRelationQueryV1.new(
            artifact_id: query.artifact_id,
            direction: query.direction,
            relation: query.relation,
            include_superseded: false,
            cursor: query.cursor,
            limit: query.first
          )
        )
      )
    end

    private

    def project_exists?(scope)
      Coordinator::Read::Repository.exists?(scope:)
    end

    def project_artifact(scope, artifact_id)
      return unless project_exists?(scope)

      artifact = @artifacts.fetch(artifact_id)&.artifact
      artifact if artifact&.scope == scope
    end
  end
end
