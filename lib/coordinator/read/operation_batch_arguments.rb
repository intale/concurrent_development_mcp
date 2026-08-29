# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchArguments
    def call(document)
      case document
      when Coordinator::Write::CommandInputDocuments::PublishSkillRevisionV2
        skill_arguments(document)
      when Coordinator::Write::CommandInputDocuments::CaptureDevelopmentArtifactV2
        artifact_arguments(document)
      when Coordinator::Write::CommandInputDocuments::DeclareDevelopmentArtifactRelationV1
        relation_arguments(document)
      end
    end

    private

    def skill_arguments(document)
      input = document.input
      common_arguments(document).merge(
        name: input.name,
        scope: input.scope,
        expected_revision: input.expected_revision,
        description: input.description,
        instructions: input.instructions,
        assets: input.assets.map do |asset|
          {
            path: asset.path,
            executable: asset.executable,
            content: asset.content.to_h.slice(:encoding, :media_type, :text, :base64)
          }
        end
      )
    end

    def artifact_arguments(document)
      artifact = document.input.artifact
      common_arguments(document).merge(
        scope: artifact.scope,
        title: artifact.title,
        kind: artifact.kind,
        labels: artifact.labels,
        content: artifact_content(artifact.content),
        source: artifact.source.to_h
      )
    end

      def artifact_content(content)
        content.to_h.slice(:encoding, :media_type, :text, :base64)
      end

    def relation_arguments(document)
      input = document.input
      relation = input.artifact_relation
      arguments = common_arguments(document).merge(
        source_artifact_id: relation.source_artifact_id,
        relation: relation.relation,
        target: relation.target.to_h,
        attributes: relation.relation_attributes.to_h.compact
      )
      if input.supersedes_relation_id
        arguments[:supersedes] = {
          relation_id: input.supersedes_relation_id,
          reason: input.supersession_reason
        }
      end
      arguments
    end

    def common_arguments(document)
      actor = document.input.actor
      {
        command_id: document.command_id,
        actor: { kind: actor.actor_kind, id: actor.actor_id }
      }
    end
  end
end
