# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelationFollowAction
    def call(direction:, source_artifact_id:, target:)
      return artifact_action(source_artifact_id) if direction == "incoming"
      return unless target.status == "verified"

      case target.kind
      when "artifact" then artifact_action(target.id)
      when "change_set" then change_set_action(target.id)
      when "work_item" then work_item_action(target.id)
      when "attempt" then attempt_action(target.id)
      when "candidate" then candidate_action(target.id)
      when "decision" then decision_action(target.id)
      when "skill" then skill_action(target)
      when "repository" then repository_action(target)
      when "operation_batch" then operation_batch_action(target.id)
      end
    end

    private

    def artifact_action(artifact_id)
      # Pre-cutover artifact IDs can appear in projected relations until
      # MIGRATION-01 rebuilds the read side. They are intentionally not valid
      # write-side NextAction arguments, so omit the convenience action.
      return unless Types::DevelopmentArtifactId.valid?(artifact_id)

      Coordinator::Write::NextAction.new(
        tool: "development_artifact_get",
        arguments: Coordinator::Write::NextAction::DevelopmentArtifactArguments.new(artifact_id:)
      )
    end

    def change_set_action(change_set_id)
      Coordinator::Write::NextAction.new(
        tool: "coord_context",
        arguments: Coordinator::Write::NextAction::ChangeSetArguments.new(change_set_id:)
      )
    end

    def work_item_action(work_item_id)
      Coordinator::Write::NextAction.new(
        tool: "coord_context",
        arguments: Coordinator::Write::NextAction::WorkItemArguments.new(work_item_id:)
      )
    end

    def attempt_action(attempt_id)
      Coordinator::Write::NextAction.new(
        tool: "coord_context",
        arguments: Coordinator::Write::NextAction::AttemptArguments.new(attempt_id:)
      )
    end

    def candidate_action(candidate_id)
      Coordinator::Write::NextAction.new(
        tool: "candidate_get",
        arguments: Coordinator::Write::NextAction::CandidateArguments.new(candidate_id:)
      )
    end

    def decision_action(decision_id)
      Coordinator::Write::NextAction.new(
        tool: "decision_get",
        arguments: Coordinator::Write::NextAction::DecisionArguments.new(decision_id:)
      )
    end

    def skill_action(target)
      return unless target.name && target.scope

      Coordinator::Write::NextAction.new(
        tool: "skill_get",
        arguments: Coordinator::Write::NextAction::SkillArguments.new(
          name: target.name,
          scope: target.scope
        )
      )
    end

    def repository_action(target)
      return unless target.name && target.scope

      Coordinator::Write::NextAction.new(
        tool: "repository_list",
        arguments: Coordinator::Write::NextAction::RepositoryArguments.new(
          scope: target.scope,
          repository_key: target.name
        )
      )
    end

    def operation_batch_action(batch_id)
      Coordinator::Write::NextAction.new(
        tool: "operation_batch_get",
        arguments: Coordinator::Write::NextAction::OperationBatchArguments.new(batch_id:)
      )
    end
  end
end
