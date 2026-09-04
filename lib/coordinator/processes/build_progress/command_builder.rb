# frozen_string_literal: true

module Coordinator::Processes
  module BuildProgress
    class CommandBuilder
      ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "build-progress")
      RULE_VERSION = "dependency-satisfaction/v1"

      def initialize(compound_marker_builder: CompoundMarkerBuilder.new)
        @compound_marker_builder = compound_marker_builder
      end

      def call(source:, dependency:, command_id:)
        document = Coordinator::Write::ProcessDecisions::DependencySatisfactionV1.new(
          schema: "process-decision/dependency-satisfaction/v1",
          process_manager: "build-progress",
          policy_version: RULE_VERSION,
          source_event: source.reference,
          change_set_id: source.change_set_id,
          dependency_id: dependency.dependency_id,
          process_step: "satisfy-work-item-dependency"
        )
        compound_marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "process-decision",
            components: document.component_markers
          )
        )
        identity = Coordinator::Write::DependencySatisfactionDecisionIdentity.new(
          document:,
          compound_marker:,
          command_id:
        )

        Coordinator::Write::Commands::SatisfyWorkItemDependency.new(
          command_id:,
          actor: ACTOR,
          change_set_id: source.change_set_id,
          dependency_id: dependency.dependency_id,
          source_event: source.reference,
          rule_version: RULE_VERSION,
          decision_identity: identity
        )
      end

      def completion(source:, command_id:)
        release_set_id = source.payload.release_set_id if
          source.payload.is_a?(Coordinator::Write::Events::ReleaseSetCompletedV2)
        document = Coordinator::Write::ProcessDecisions::ChangeSetCompletionV1.new(
          schema: "process-decision/change-set-completion/v1",
          process_manager: "build-progress",
          policy_version: "change-set-completion/v1",
          source_event: source.reference,
          change_set_id: source.change_set_id,
          release_set_id:,
          process_step: "complete-change-set"
        )
        compound_marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "process-decision",
            components: document.component_markers
          )
        )
        identity = Coordinator::Write::ChangeSetCompletionDecisionIdentity.new(
          document:,
          compound_marker:,
          command_id:
        )

        Coordinator::Write::Commands::CompleteChangeSet.new(
          command_id:,
          actor: ACTOR,
          change_set_id: source.change_set_id,
          source_event: source.reference,
          release_set_id:,
          rule_version: "change-set-completion/v1",
          decision_identity: identity
        )
      end
    end
  end
end
