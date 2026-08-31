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

    def catalog(query)
      project = find_project(query.repository_id)
      return unless project

      Coordinator::Read::Web::KnowledgeBrowserV1::Catalog.new(
        project: build_project(project),
        skills: @skills.page(
          Coordinator::Read::SkillListQueryV1.new(
            name: query.skill_name,
            scope: project.scope,
            after_skill_id: query.after_skill_id,
            limit: query.first
          )
        ),
        artifacts: @artifacts.page(
          Coordinator::Read::DevelopmentArtifactListQueryV1.new(
            scope: project.scope,
            kind: query.artifact_kind,
            labels: query.artifact_labels,
            source_kind: query.artifact_source_kind,
            relation_target_kind: nil,
            relation_target_id: nil,
            after_global_position: query.after_artifact_global_position,
            limit: query.first
          )
        )
      )
    end

    def skill(query)
      project = find_project(query.repository_id)
      return unless project

      skill = @skills.fetch(name: query.name, scope: project.scope)
      skill && Coordinator::Read::Web::KnowledgeBrowserV1::SkillDetail.new(
        project: build_project(project),
        skill:
      )
    end

    def skill_asset(query)
      project = find_project(query.repository_id)
      return unless project

      asset = @skills.fetch_asset(name: query.name, scope: project.scope, path: query.path)
      asset && Coordinator::Read::Web::KnowledgeBrowserV1::SkillAssetDetail.new(
        project: build_project(project),
        asset:
      )
    end

    def artifact(query)
      project = find_project(query.repository_id)
      return unless project

      artifact = @artifacts.fetch(query.artifact_id)&.artifact
      return unless artifact&.scope == project.scope

      Coordinator::Read::Web::KnowledgeBrowserV1::ArtifactDetail.new(
        project: build_project(project),
        artifact:,
        content: @artifacts.fetch_content(query.artifact_id),
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

    def find_project(repository_id)
      Coordinator::Read::Repository.find_by(repository_id:)
    end

    def build_project(record)
      Coordinator::Read::Web::KnowledgeBrowserV1::Project.new(
        repository_id: record.repository_id,
        scope: record.scope,
        display_name: record.display_name
      )
    end
  end
end
