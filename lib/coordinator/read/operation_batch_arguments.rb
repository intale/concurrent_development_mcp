# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchArguments
    def call(document)
      case document
      when Coordinator::Write::CommandInputDocuments::PublishSkillRevisionV1,
           Coordinator::Write::CommandInputDocuments::PublishSkillRevisionV2
        skill_arguments(document)
      when Coordinator::Write::CommandInputDocuments::CaptureDevelopmentArtifactV1,
           Coordinator::Write::CommandInputDocuments::CaptureDevelopmentArtifactV2
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
          if asset.is_a?(Coordinator::Write::CommandInputDocuments::SkillAssetV2)
            {
              path: asset.path,
              executable: asset.executable,
              content: asset.content.to_h.slice(:encoding, :media_type, :text, :base64)
            }
          else
            asset.to_h.slice(:path, :media_type, :executable, :content_base64)
          end
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
      if content.is_a?(Coordinator::Write::Content::TextV1) ||
         content.is_a?(Coordinator::Write::Content::BinaryV1)
        return content.to_h.slice(:encoding, :media_type, :text, :base64)
      end

      common = { encoding: content.encoding, media_type: content.media_type }
      if content.encoding == "utf-8"
        common.merge(text: content.content_base64.unpack1("m0").force_encoding(Encoding::UTF_8))
      else
        common.merge(base64: content.content_base64)
      end
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
