# frozen_string_literal: true

module Coordinator::Read
  # Formats already validated command instructions for public read responses.
  class OperationBatchArguments
    def call(document)
      document = CommandResults::Source.document(document)
      input = document.fetch(:input)
      actor = input.fetch(:actor)
      common = { command_id: document.fetch(:command_id),
        actor: { kind: actor.fetch(:actor_kind), id: actor.fetch(:actor_id) } }
      case document.fetch(:tool_name)
      when "skill_publish"
        common.merge(input.slice(:name, :scope, :expected_revision, :description, :instructions)).merge(
          assets: input.fetch(:assets).map { _1.slice(:path, :executable).merge(content: content(_1.fetch(:content))) }
        )
      when "development_artifact_capture"
        artifact = input.fetch(:artifact)
        common.merge(artifact.slice(:scope, :title, :kind, :labels, :source)).merge(content: content(artifact.fetch(:content)))
      when "development_artifact_relation_declare"
        relation = input.fetch(:artifact_relation)
        arguments = common.merge(relation.slice(:source_artifact_id, :relation, :target)).merge(attributes: relation.fetch(:attributes).compact)
        if input[:supersedes_relation_id]
          arguments[:supersedes] = { relation_id: input.fetch(:supersedes_relation_id), reason: input.fetch(:supersession_reason) }
        end
        arguments
      end
    end

    private

    def content(document)
      document.slice(:encoding, :media_type, :text, :base64)
    end
  end
end
