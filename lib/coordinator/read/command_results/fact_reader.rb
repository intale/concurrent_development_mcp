# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class FactReader
      def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
        @event_store, @stream_factory = event_store, stream_factory
      end

      def call(terminal)
        command_id = terminal.stream.stream_id
        registration = first(:command, command_id, "CommandRegistered")
        instruction = instruction_for(command_id, registration)
        return unless instruction

        effects = @event_store.read_command_events(Coordinator::Write::CommandEventReadCriteria.new(
          command_id:, through_global_position: terminal.global_position,
          maximum_count: Coordinator::Shared::Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS
        ))
        if registration.data.fetch("tool_name") == "work_intention_set_renew"
          effects += renewal_effects(command_id, terminal.global_position)
        end
        Source.new(terminal_event: terminal, registration:, input: instruction.fetch("input"), persisted_events: effects)
      end

      def history(stream, id, types, maximum_count:, to_revision: nil)
        @event_store.read(@stream_factory.public_send(stream, id), Coordinator::Write::EventReadCriteria.new(
          event_types: types, maximum_count:, direction: :asc, to_revision:
        ))
      end

      def first(stream, id, type)
        history(stream, id, [ type ], maximum_count: 1).first
      end

      def at(stream, id, revision)
        @event_store.read_at(@stream_factory.public_send(stream, id), revision)
      end

      def previous(stream, id, types, revision)
        @event_store.read_latest(@stream_factory.public_send(stream, id), Coordinator::Write::LatestEventReadCriteria.new(
          event_types: types, from_revision: revision
        ))
      end

      def indexed(context:, stream:, types:, marker:, through_position:)
        @event_store.read_global_marked(Coordinator::Write::GlobalMarkedEventReadCriteria.new(
          stream_context: context, stream_name: stream, event_types: types, markers: [ marker ],
          maximum_count: 1, direction: :asc, to_position: through_position
        )).first
      end

      def latest(context:, stream:, types:, marker:, through_position:)
        @event_store.read_latest_global_marked(Coordinator::Write::GlobalMarkedEventReadCriteria.new(
          stream_context: context, stream_name: stream, event_types: types, markers: [ marker ],
          maximum_count: 1, direction: :desc, from_position: through_position
        ))
      end

      def marked(stream, id, type, marker)
        @event_store.read_marked(@stream_factory.public_send(stream, id), Coordinator::Write::MarkedEventReadCriteria.new(
          event_type: type, marker:, maximum_count: 1, direction: :asc
        )).first
      end

      private

      def instruction_for(command_id, registration)
        task = indexed(context: "CoordinatorControl", stream: "CoordinationTask", types: [ "CoordinationTaskSubmitted" ],
          marker: "command:#{command_id}", through_position: nil)
        return task.data.fetch("command_input") if task

        batch_marker = registration.markers.find { _1.start_with?("operation-batch:") }
        item_marker = registration.markers.find { _1.start_with?("batch-item:") }
        return unless batch_marker && item_marker

        item = marked(:operation_batch, batch_marker.delete_prefix("operation-batch:"), "OperationBatchItemEnqueued", item_marker)
        item.data.fetch("input")
      end

      def renewal_effects(id, through_position)
        history(:work_intention_set_renewal, id, %w[WorkIntentionRenewalCompleted], maximum_count: 32)
          .select { _1.global_position <= through_position }.filter_map do |event|
          reference = event.data.fetch("renewal_event")
          next unless reference

          at(:resource_work_intention, reference.fetch("stream_id"), reference.fetch("stream_revision"))
        end
      end
    end
  end
end
