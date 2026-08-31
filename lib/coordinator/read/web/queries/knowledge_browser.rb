# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class KnowledgeBrowser
    def initialize(
      catalog_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Catalog.new,
      skill_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Skill.new,
      skill_asset_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::SkillAsset.new,
      artifact_contract: Coordinator::Read::Web::Contracts::KnowledgeBrowser::Artifact.new,
      repository: Coordinator::Read::Web::Repositories::KnowledgeBrowser.new
    )
      @catalog_contract = catalog_contract
      @skill_contract = skill_contract
      @skill_asset_contract = skill_asset_contract
      @artifact_contract = artifact_contract
      @repository = repository
    end

    def catalog(input)
      validated = validate(@catalog_contract, input)
      @repository.catalog(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Catalog.new(
          repository_id: validated[:repository_id],
          first: validated[:first] || 20,
          skill_name: validated[:skill_name],
          after_skill_id: validated[:after_skill_id],
          artifact_kind: validated[:artifact_kind],
          artifact_labels: validated[:artifact_labels] || [],
          artifact_source_kind: validated[:artifact_source_kind],
          after_artifact_global_position: validated[:after_artifact_global_position]
        )
      )
    end

    def skill(input)
      validated = validate(@skill_contract, input)
      @repository.skill(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Skill.new(
          repository_id: validated[:repository_id],
          name: validated[:name]
        )
      )
    end

    def skill_asset(input)
      validated = validate(@skill_asset_contract, input)
      @repository.skill_asset(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::SkillAsset.new(
          repository_id: validated[:repository_id],
          name: validated[:name],
          path: validated[:path]
        )
      )
    end

    def artifact(input)
      validated = validate(@artifact_contract, input)
      cursor = validated[:cursor] || {
        after_observed_sequence: 0,
        through_observed_sequence: nil,
        after_declared_global_position: nil,
        after_relation_id: nil
      }
      @repository.artifact(
        Coordinator::Read::Web::KnowledgeBrowserQueryV1::Artifact.new(
          repository_id: validated[:repository_id],
          artifact_id: validated[:artifact_id],
          first: validated[:first] || 20,
          direction: validated[:direction] || "both",
          relation: validated[:relation],
          cursor: Coordinator::Read::DevelopmentArtifactRelationPageV1::Cursor.new(cursor)
        )
      )
    end

    private

    def validate(contract, input)
      validated = contract.call(input)
      raise Coordinator::Read::Web::KnowledgeBrowserQueryError, validated.errors.to_h if validated.failure?

      validated
    end
  end
end
