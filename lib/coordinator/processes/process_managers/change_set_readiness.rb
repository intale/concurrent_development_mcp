# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class ChangeSetReadiness
      HANDLED_OUTCOME_CODES = %i[
        readiness_already_decided
        work_item_already_ready
        work_item_not_planned
        incoming_dependency_unsatisfied
      ].freeze

      def initialize(
        event_store:,
        source_builder: ChangeSetActivationSourceBuilder.new,
        targets_builder: ReadinessTargetsBuilder.new,
        command_builder: ReadinessCommandBuilder.new,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        operation: Coordinator::Write::Operations::ExecuteEvaluateWorkItemReadiness.new(event_store:),
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new
      )
        @event_store = event_store
        @source_builder = source_builder
        @targets_builder = targets_builder
        @command_builder = command_builder
        @process_step_planner = process_step_planner
        @operation = operation
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(event)
        source = @source_builder.call(event)
        targets = @targets_builder.call(
          source:,
          memberships: load_memberships(source.payload.change_set_id)
        )

        targets.work_item_ids.each do |work_item_id|
          process_step = @process_step_planner.call(
            source_event: source.event,
            process_name: "change-set-readiness",
            step_name: "evaluate-work-item-readiness",
            subject_kind: "work-item",
            subject_id: work_item_id,
            rule_version: "change-set-readiness/v1",
            allocate_target_entity: false
          )
          command = @command_builder.call(
            source:,
            work_item_id:,
            command_id: process_step.target_command_id
          )
          result = @operation.call(
            Coordinator::Write::ReadinessInvocation.new(
              command:,
              source_event: source.event,
              source_reference: source.reference,
              source_change_set_id: source.payload.change_set_id,
              caused_by: process_step.event
            )
          )
          handle_result!(result, command:)
        end

        nil
      end

      private

      def load_memberships(change_set_id)
        @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentExecution",
            stream_name: "WorkItem",
            event_types: [ "WorkItemAddedToChangeSet" ],
            markers: [ "change-set:#{change_set_id}" ],
            maximum_count: 100,
            direction: :asc
          )
        ).map do |event|
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        end
      end

      def handle_result!(result, command:)
        return if result.success?
        return if HANDLED_OUTCOME_CODES.include?(result.failure.code)

        raise ReadinessTargetRejected,
              "#{command.work_item_id}: #{result.failure.code} - #{result.failure.message}"
      end
    end
  end
end
