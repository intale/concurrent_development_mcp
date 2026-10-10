# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAssignOperationBatchItemCommand
      include Dry::Monads[:result]

      def initialize(
        event_store:, loader: OperationBatches::Loader.new(event_store:),
        decider: Domain::OperationBatches::AssignItemCommand.new,
        request_marker: CommandLifecycle::RequestMarker.new,
        schema_registry: EventSchemaRegistry.new, stream_factory: StreamFactory.new,
        event_factory: EventFactory.new, id_generator: IdGenerator.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @request_marker = request_marker
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @event_factory = event_factory
        @id_generator = id_generator
      end

      def call_command(command, caused_by: nil)
        event_ids = Array.new(2) { @id_generator.uuid_v7 }
        correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
        @event_store.multiple do
          snapshot = @loader.item(command.batch_id, command.index)
          item = snapshot.state.item(command.index)
          previous = snapshot.physical_events.find do |event|
            %w[OperationBatchItemCommandAssigned OperationBatchItemRegistrationRejected].include?(event.type)
          end
          next Success(OperationBatches::AssignmentV1.new(item:, event: previous)) if previous

          input_actor = item&.command_input&.input&.actor
          actor = input_actor && Commands::Actor.new(kind: input_actor.actor_kind, id: input_actor.actor_id)
          registration = item && registration_for(actor:, request_id: item.request_id)
          decision = @decider.call(state: snapshot.state, command:, registration:)
          next decision if decision.failure?

          plan = decision.value!
          if plan.writes.any? { _1.event.is_a?(Events::CommandRegisteredV1) }
            ensure_command_id_available!(item.command_id)
          end
          assignment = persist(plan, command:, item:, actor:, event_ids:, correlation_id:, caused_by:)
          if assignment.type == "OperationBatchItemCommandAssigned"
            document = item.command_input.class.new(item.command_input.attributes.merge(command_id: assignment.data.fetch("command_id")))
            item = OperationBatches::ItemV2.new(item.attributes.merge(command_input: document))
          end
          Success(OperationBatches::AssignmentV1.new(item:, event: assignment))
        end
      end

      private

      def registration_for(actor:, request_id:)
        event = @event_store.read_global_marked(GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl", stream_name: "Command",
          event_types: [ "CommandRegistered" ],
          markers: [ @request_marker.call(actor:, request_id:) ], maximum_count: 1, direction: :asc
        )).first
        return unless event

        OperationBatches::RegistrationV1.new(
          payload: @schema_registry.load(type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data),
          canonical_input_digest: event.metadata.fetch("canonical_input_digest")
        )
      end

      def ensure_command_id_available!(command_id)
        return if @event_store.read(@stream_factory.command(command_id), EventQueries::COMMAND_REGISTRATION).empty?

        raise InvalidCommandHistory, "Proposed batch-item Command ID is already in use"
      end

      def persist(plan, command:, item:, actor:, event_ids:, correlation_id:, caused_by:)
        first = nil
        plan.writes.each_with_index do |write, index|
          registration = write.event.is_a?(Events::CommandRegisteredV1)
          metadata = if registration
                       Metadata::CanonicalCommandV1.new(
                         command_id: write.event.command_id, actor_kind: actor.kind, actor_id: actor.id,
                         recorded_by: "coordinator", policy_version: "operation-batch/v2",
                         canonical_input_digest: item.canonical_input_digest
                       )
          else
                       common = {
                         command_id: command.command_id, actor_kind: command.actor.kind, actor_id: command.actor.id,
                         recorded_by: "coordinator", policy_version: "operation-batch/v2"
                       }
                       write.event.is_a?(Events::OperationBatchItemCommandAssignedV1) ?
                         Metadata::OperationBatchItemAssignmentV1.new(**common, canonical_input_digest: item.canonical_input_digest) :
                         EventMetadata.new(common)
          end
          markers = [ "operation-batch:#{command.batch_id}", "batch-item:#{command.batch_id}:#{command.index}" ]
          if registration
            markers.concat([ "command:#{write.event.command_id}", "tool:#{item.tool_name}",
                             @request_marker.call(actor:, request_id: item.request_id) ])
          else
            markers << "command:#{command.command_id}"
          end
          event = @event_factory.build!(
            event: write.event, event_id: event_ids.fetch(index), metadata:, markers:,
            correlation_id:, caused_by: registration ? first : caused_by
          )
          persisted = @event_store.append(write.stream, [ event ]).sole
          first ||= persisted
        end
        first
      end
    end
  end
end
