# frozen_string_literal: true

module Coordinator
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
        operation: Operations::ExecuteEvaluateWorkItemReadiness.new(event_store:),
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @source_builder = source_builder
        @targets_builder = targets_builder
        @command_builder = command_builder
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
          command = @command_builder.call(source:, work_item_id:)
          result = @operation.call(ReadinessInvocation.new(command:, source:))
          handle_result!(result, command:)
        end

        nil
      end

      private

      def load_memberships(change_set_id)
        @event_store.read(
          @stream_factory.change_set(change_set_id),
          EventQueries::CHANGE_SET_MEMBERS_FOR_READINESS
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
