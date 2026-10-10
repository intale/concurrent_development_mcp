# frozen_string_literal: true

module Coordinator::Read::Search
  module Retrieval
    class SkillArguments < Coordinator::Read::Value
      attribute :name, Coordinator::Read::Types::SkillName
      attribute :scope, Coordinator::Read::Types::SkillScope
      attribute :revision, Coordinator::Read::Types::Integer.constrained(gteq: 1)
    end

    class AssetArguments < SkillArguments
      attribute :path, Coordinator::Read::Types::SkillAssetPath
    end

    class ResourceArguments < Coordinator::Read::Value
      attribute :resource_id, Coordinator::Read::Types::ResourceId
    end

    class ArtifactArguments < Coordinator::Read::Value
      attribute :artifact_id, Coordinator::Read::Types::DevelopmentArtifactId
      attribute? :observation_id, Coordinator::Read::Types::DevelopmentArtifactObservationId
    end

    class GuidanceArguments < Coordinator::Read::Value
      attribute :message_id, Coordinator::Read::Types::Identifier
    end

    class ChoiceArguments < Coordinator::Read::Value
      attribute :choice_id, Coordinator::Read::Types::Identifier
    end

    class DecisionArguments < Coordinator::Read::Value
      attribute :decision_id, Coordinator::Read::Types::Identifier
    end

    class WorkItemArguments < Coordinator::Read::Value
      attribute :change_set_id, Coordinator::Read::Types::Identifier
      attribute :work_item_id, Coordinator::Read::Types::Identifier
    end

    class Skill < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("skill_get")
      attribute :arguments, SkillArguments
    end

    class Asset < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("skill_asset_get")
      attribute :arguments, AssetArguments
    end

    class Resource < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("resource_get")
      attribute :arguments, ResourceArguments
    end

    class ArtifactContent < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("development_artifact_content_get")
      attribute :arguments, ArtifactArguments
    end

    class ArtifactMetadata < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("development_artifact_get")
      attribute :arguments, ArtifactArguments
    end

    class Guidance < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("guidance_get")
      attribute :arguments, GuidanceArguments
    end

    class Choice < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("agent_choice_get")
      attribute :arguments, ChoiceArguments
    end

    class Decision < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("decision_get")
      attribute :arguments, DecisionArguments
    end

    class WorkItem < Coordinator::Read::Value
      attribute :tool, Coordinator::Read::Types::String.enum("coord_context")
      attribute :arguments, WorkItemArguments
    end

    Type = Skill | Asset | Resource | ArtifactContent | ArtifactMetadata | Guidance | Choice | Decision | WorkItem
    CLASSES = {
      "skill_get" => Skill, "skill_asset_get" => Asset, "resource_get" => Resource,
      "development_artifact_content_get" => ArtifactContent, "guidance_get" => Guidance,
      "agent_choice_get" => Choice, "decision_get" => Decision, "coord_context" => WorkItem
    }.freeze

    def self.call(input)
      return [] unless input

      tool = input.fetch("tool")
      action = CLASSES.fetch(tool).new(tool:, arguments: input.fetch("arguments").transform_keys(&:to_sym))
      actions = [ action ]
      if tool == "development_artifact_content_get"
        actions << ArtifactMetadata.new(tool: "development_artifact_get", arguments: action.arguments)
      end
      actions
    end
  end
end
