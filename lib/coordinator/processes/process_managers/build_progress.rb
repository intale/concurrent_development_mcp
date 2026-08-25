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
        dependency_already_satisfied
        dependency_source_mismatch
      ].freeze

      def initialize(
        event_store:,
        source_builder: Coordinator::Processes::BuildProgress::SourceBuilder.new,
        command_builder: Coordinator::Processes::BuildProgress::CommandBuilder.new,
        satisfy_dependency: Coordinator::Write::Operations::ExecuteSatisfyWorkItemDependency.new(event_store:),
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new
      )
        @event_store = event_store
        @source_builder = source_builder
        @command_builder = command_builder
        @satisfy_dependency = satisfy_dependency
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(event)
        source = @source_builder.call(event)
        dependencies_for(source).each do |dependency|
          command = @command_builder.call(source:, dependency:)
          result = @satisfy_dependency.call_command(command)
          handle_result!(result, command:)
        end
        nil
      end

      private

      def dependencies_for(source)
        kinds = SOURCE_DEPENDENCY_KINDS.fetch(source.payload.class)
        load_change_set(source.change_set_id).dependencies.select do |dependency|
          kinds.include?(dependency.dependency_kind)
        end
      end

      def load_change_set(change_set_id)
        events = @event_store.read(
          @stream_factory.change_set(change_set_id),
          Coordinator::Write::EventQueries::CHANGE_SET_FOR_DEPENDENCY_SATISFACTION
        ).map do |event|
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        end
        Coordinator::Write::Domain::ChangeSets::State.reduce(events)
      end

      def handle_result!(result, command:)
        return if result.success?
        return if HANDLED_OUTCOME_CODES.include?(result.failure.code)

        failure = result.failure
        raise BuildProgressProcessRejected,
              "#{command.dependency_id}: #{failure.code} - #{failure.message}"
      end
    end
  end
end
