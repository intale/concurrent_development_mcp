# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class BuildProgress
      SOURCE_DEPENDENCY_KINDS = {
        Coordinator::Write::Events::WorkItemCandidateSelectedV1 => %w[requires_candidate],
        Coordinator::Write::Events::WorkItemCompletedV1 => %w[requires_completion requires_artifact requires_contract],
        Coordinator::Write::Events::RepositoryIntegrationRecordedV1 => %w[must_integrate_after],
        Coordinator::Write::Events::ReleaseSetVerificationRecordedV1 => %w[requires_composite_verification],
        Coordinator::Write::Events::ReleaseSetCompletedV1 => %w[must_deploy_after]
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
        source_builder: Coordinator::Processes::BuildProgress::SourceBuilder.new,
        command_builder: Coordinator::Processes::BuildProgress::CommandBuilder.new,
        satisfy_dependency: Coordinator::Write::Operations::ExecuteSatisfyWorkItemDependency.new(event_store:),
        complete_change_set: Coordinator::Write::Operations::ExecuteCompleteChangeSet.new(event_store:),
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new
      )
        @event_store = event_store
        @source_builder = source_builder
        @command_builder = command_builder
        @satisfy_dependency = satisfy_dependency
        @complete_change_set = complete_change_set
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(event)
        source = @source_builder.call(event)
        dependencies_for(source).each do |dependency|
          command = @command_builder.call(source:, dependency:)
          result = @satisfy_dependency.call_command(command)
          handle_result!(result, identifier: command.dependency_id)
        end
        complete(source) if completion_source?(source)
        nil
      end

      private

      def completion_source?(source)
        source.payload.is_a?(Coordinator::Write::Events::WorkItemCompletedV1) ||
          source.payload.is_a?(Coordinator::Write::Events::ReleaseSetCompletedV1)
      end

      def complete(source)
        command = @command_builder.completion(source:)
        result = @complete_change_set.call_command(command)
        handle_result!(result, identifier: command.change_set_id)
      end

      def dependencies_for(source)
        kinds = SOURCE_DEPENDENCY_KINDS.fetch(source.payload.class)
        @event_store.read(
          @stream_factory.change_set(source.change_set_id),
          Coordinator::Write::EventQueries::CHANGE_SET_FOR_DEPENDENCY_SATISFACTION
        ).filter_map do |event|
          payload = @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
          next unless payload.is_a?(Coordinator::Write::Events::WorkItemDependencyDeclaredV1)
          next unless kinds.include?(payload.dependency_kind)

          payload
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
