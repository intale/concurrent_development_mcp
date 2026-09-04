# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class BuildProgress
      SOURCE_DEPENDENCY_KINDS = {
        Coordinator::Write::Events::WorkItemCandidateSelectedV1 => %w[requires_candidate],
        Coordinator::Write::Events::WorkItemCandidateSelectedV2 => %w[requires_candidate],
        Coordinator::Write::Events::WorkItemCompletedV1 => %w[requires_completion requires_artifact requires_contract],
        Coordinator::Write::Events::WorkItemCompletedV2 => %w[requires_completion requires_artifact requires_contract],
        Coordinator::Write::Events::RepositoryIntegrationRecordedV2 => %w[must_integrate_after],
        Coordinator::Write::Events::ReleaseSetVerificationRecordedV2 => %w[requires_composite_verification],
        Coordinator::Write::Events::ReleaseSetCompletedV2 => %w[must_deploy_after]
      }.freeze
      HANDLED_OUTCOME_CODES = %i[
        change_set_not_active
        change_set_already_completed
        change_set_completion_source_mismatch
        dependency_already_satisfied
        dependency_source_mismatch
        dependency_unsatisfied
        release_change_set_mismatch
        release_coverage_mismatch
        release_not_activated
        release_required
        work_item_completion_invalid
        work_item_incomplete
      ].freeze

      def initialize(
        event_store:,
        source_builder: Coordinator::Processes::BuildProgress::SourceBuilder.new(event_store:),
        command_builder: Coordinator::Processes::BuildProgress::CommandBuilder.new,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        satisfy_dependency: Coordinator::Write::Operations::ExecuteSatisfyWorkItemDependency.new(event_store:),
        complete_change_set: Coordinator::Write::Operations::ExecuteCompleteChangeSet.new(event_store:),
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new,
        change_set_state_loader: Coordinator::Write::ChangeSets::StateLoader.new(event_store:)
      )
        @event_store = event_store
        @source_builder = source_builder
        @command_builder = command_builder
        @process_step_planner = process_step_planner
        @satisfy_dependency = satisfy_dependency
        @complete_change_set = complete_change_set
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @change_set_state_loader = change_set_state_loader
      end

      def call(event)
        source = @source_builder.call(event)
        dependencies_for(source).each do |dependency|
          process_step = @process_step_planner.call(
            source_event: source.event,
            process_name: "build-progress",
            step_name: "satisfy-work-item-dependency",
            subject_kind: "work-item-dependency",
            subject_id: dependency.dependency_id,
            rule_version: Coordinator::Processes::BuildProgress::CommandBuilder::RULE_VERSION,
            allocate_target_entity: false
          )
          command = @command_builder.call(source:, dependency:, command_id: process_step.target_command_id)
          result = @satisfy_dependency.call_command(command, caused_by: process_step.event)
          handle_result!(result, identifier: command.dependency_id)
        end
        complete(source) if completion_source?(source)
        nil
      end

      private

      def completion_source?(source)
        source.payload.is_a?(Coordinator::Write::Events::WorkItemCompletedV1) ||
          source.payload.is_a?(Coordinator::Write::Events::WorkItemCompletedV2) ||
          source.payload.is_a?(Coordinator::Write::Events::ReleaseSetCompletedV2)
      end

      def complete(source)
        process_step = @process_step_planner.call(
          source_event: source.event,
          process_name: "build-progress",
          step_name: "complete-change-set",
          subject_kind: "change-set",
          subject_id: source.change_set_id,
          rule_version: "change-set-completion/v1",
          allocate_target_entity: false
        )
        command = @command_builder.completion(source:, command_id: process_step.target_command_id)
        result = @complete_change_set.call_command(command, caused_by: process_step.event)
        handle_result!(result, identifier: command.change_set_id)
      end

      def dependencies_for(source)
        kinds = SOURCE_DEPENDENCY_KINDS.fetch(source.payload.class)
        @change_set_state_loader.call(source.change_set_id).dependencies.select do |dependency|
          kinds.include?(dependency.dependency_kind)
        end
      end

      def handle_result!(result, identifier:)
        return if result.success?
        return if HANDLED_OUTCOME_CODES.include?(result.failure.code)

        failure = result.failure
        raise BuildProgressProcessRejected,
              "#{identifier}: #{failure.code} - #{failure.message}"
      end
    end
  end
end
