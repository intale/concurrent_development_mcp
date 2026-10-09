# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class InstructionLoader
      def initialize(
        event_store:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new,
        target_command_builder: Coordinator::Write::Tasks::TargetCommandBuilder.new,
        batch_item_builder: Coordinator::Write::OperationBatches::ItemBuilder.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @target_command_builder = target_command_builder
        @batch_item_builder = batch_item_builder
      end

      def for_registration(registration)
        state = CommandState.reduce(events: [ registration ], payloads: [ load_payload(registration) ])
        unless registration.stream.stream_id == state.command_id && registration.stream_revision.zero?
          raise InvalidProjectionSource, "Command registration identity is inconsistent"
        end

        call(state, registration:)
      end

      def call(command_state, registration:)
        task_submission = find_task_submission(command_state.command_id)
        return validated_command_input(
          load_payload(task_submission).command_input,
          command_state:,
          registration:
        ) if task_submission

        batch_item = find_batch_item(command_state.command_id, registration:)
        unless batch_item
          # Internal policy commands have no client instruction or public result.
          # A missing instruction for a public command is still corrupt history.
          return unless Coordinator::Write::Tasks::TargetContractRegistry.tool_names.include?(command_state.tool_name)

          raise InvalidProjectionSource, "Command has no Task or Operation Batch instruction"
        end

        unless batch_item.request_id == command_state.request_id &&
               batch_item.canonical_input_digest == command_state.canonical_input_digest
          raise InvalidProjectionSource, "Operation Batch item does not match its Command registration"
        end

        validated_command_input(batch_item.command_input, command_state:, registration:)
      end

      private

      def find_task_submission(command_id)
        event = @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorControl",
            stream_name: "CoordinationTask",
            event_types: [ "CoordinationTaskSubmitted" ],
            markers: [ "command:#{command_id}" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first

        event
      end

      def find_batch_item(command_id, registration:)
        batch_markers = registration.markers.grep(/\Aoperation-batch:/)
        item_markers = registration.markers.grep(/\Abatch-item:/)
        return unless batch_markers.one? && item_markers.one?

        batch_id = batch_markers.sole.delete_prefix("operation-batch:")
        event = @event_store.read_marked(
          @stream_factory.operation_batch(batch_id),
          Coordinator::Write::MarkedEventReadCriteria.new(
            event_type: "OperationBatchItemEnqueued",
            marker: item_markers.sole,
            maximum_count: 1,
            direction: :asc
          )
        ).first
        return unless event

        payload = load_payload(event)
        return unless payload.is_a?(Coordinator::Write::Events::OperationBatchItemEnqueuedV1)

        item = @batch_item_builder.call(event:, payload:)
        item if item.command_id == command_id
      end

      def validated_command_input(command_input, command_state:, registration:)
        command = @target_command_builder.call(command_input)
        actor_matches = registration.metadata.fetch("actor_kind") == command.actor.kind &&
                        registration.metadata.fetch("actor_id") == command.actor.id
        unless command.command_id == command_state.command_id &&
               command_input.tool_name == command_state.tool_name && actor_matches
          raise InvalidProjectionSource, "Persisted Command instruction does not match its registration"
        end

        command_input
      end

      def load_payload(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
