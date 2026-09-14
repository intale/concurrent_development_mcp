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
      return if query.scope && !project_exists?(query.scope)

      @skills.page(
        Coordinator::Read::SkillListQueryV1.new(
          name: query.name,
          scope: query.scope,
          after_updated_at: query.after_updated_at,
          after_skill_id: query.after_skill_id,
          order: "updated_at",
          sort: query.sort,
          limit: query.first
        )
      )
    end

    def skill_by_id(query)
      skill = @skills.fetch_by_id(query.skill_id)
      skill && Coordinator::Read::Web::KnowledgeBrowserV1::SkillDetail.new(skill:)
    end

    def skill_asset_by_id(query)
      asset = @skills.fetch_asset_by_id(skill_id: query.skill_id, path: query.path)
      asset && Coordinator::Read::Web::KnowledgeBrowserV1::SkillAssetDetail.new(asset:)
    end

    def artifacts(query)
      return unless project_exists?(query.scope)

      @artifacts.event_time_page(query)
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
