# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class KnowledgeBrowser
    def initialize(
      skills_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Skills.new,
      artifacts_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Artifacts.new,
      skill_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Skill.new,
      skill_asset_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::SkillAsset.new,
      artifact_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Artifact.new,
      relationships_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Relationships.new,
      repository: Coordinator::Read::Web::Repositories::KnowledgeBrowser.new,
      project_reference: Coordinator::Read::Web::ProjectReference.new
    )
      @skills_contract = skills_contract
      @artifacts_contract = artifacts_contract
      @skill_contract = skill_contract
      @skill_asset_contract = skill_asset_contract
      @artifact_contract = artifact_contract
      @relationships_contract = relationships_contract
      @repository = repository
      @project_reference = project_reference
    end

    def skills(input)
      values = validate(@skills_contract, input)
      @repository.skills(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Skills.new(
          **project(values),
          first: values[:first] || 20,
          name: values[:name],
          after_skill_id: values[:after_skill_id]
        )
      )
    end

    def artifacts(input)
      values = validate(@artifacts_contract, input)
      @repository.artifacts(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Artifacts.new(
          **project(values),
          first: values[:first] || 20,
          kind: values[:kind],
          labels: values[:labels] || [],
          source_kind: values[:source_kind],
          after_global_position: values[:after_global_position]
        )
      )
    end

    def skill(input)
      values = validate(@skill_contract, input)
      @repository.skill(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Skill.new(
          **project(values),
          name: values[:name]
        )
      )
    end

    def skill_asset(input)
      values = validate(@skill_asset_contract, input)
      @repository.skill_asset(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::SkillAsset.new(
          **project(values),
          name: values[:name],
          path: values[:path]
        )
      )
    end

    def artifact(input)
      values = validate(@artifact_contract, input)
      @repository.artifact(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Artifact.new(
          **project(values),
          artifact_id: values[:artifact_id]
        )
      )
    end

    def relationships(input)
      values = validate(@relationships_contract, input)
      cursor = values[:cursor] || {
        after_observed_sequence: 0,
        through_observed_sequence: nil,
        after_declared_global_position: nil,
        after_relation_id: nil
      }
      @repository.relationships(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Relationships.new(
          **project(values),
          artifact_id: values[:artifact_id],
          first: values[:first] || 20,
          direction: values[:direction] || "both",
          relation: values[:relation],
          cursor: Coordinator::Read::DevelopmentArtifactRelationPageV1::Cursor.new(cursor)
        )
      )
    end

    private

    def project(values)
      project_ref = values[:project_ref]
      { project_ref:, scope: @project_reference.decode(project_ref) }
    end

    def validate(contract, input)
      validated = contract.call(input)
      raise Coordinator::Read::Web::KnowledgeBrowserQueryError, validated.errors.to_h if validated.failure?

      validated.to_h
    end
  end
end
