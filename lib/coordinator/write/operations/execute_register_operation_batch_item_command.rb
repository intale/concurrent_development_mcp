# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRegisterOperationBatchItemCommand
      include Dry::Monads[:result]

      def initialize(event_store:, loader: OperationBatches::Loader.new(event_store:),
        registration_loader: OperationBatches::RegistrationLoader.new(event_store:),
        validation_decider: Domain::OperationBatches::AssignItemCommand.new,
        registration_decider: OperationBatches::RegisterItemCommand.new, request_marker: CommandLifecycle::RequestMarker.new,
        event_factory: EventFactory.new, stream_factory: StreamFactory.new, id_generator: IdGenerator.new)
        @event_store, @loader, @registration_loader = event_store, loader, registration_loader
        @validation_decider, @registration_decider, @request_marker = validation_decider, registration_decider, request_marker
        @event_factory, @stream_factory, @id_generator = event_factory, stream_factory, id_generator
      end

      def call_command(command, caused_by:)
        snapshot = @loader.item(command.batch_id, command.index)
        validation = @validation_decider.call(state: snapshot.state,
          command: Commands::AssignOperationBatchItemCommand.new(command.to_h), registration: nil)
        return validation if validation.failure?
        item = snapshot.state.item(command.index)
        unless command.command_id == item.command_id
          raise InvalidCommandHistory, "Registration command does not match the proposed item identity"
        end
        input_actor = item.command_input.input.actor
        actor = Commands::Actor.new(kind: input_actor.actor_kind, id: input_actor.actor_id)
        event_id = @id_generator.uuid_v7
        @event_store.multiple do
          existing = @registration_loader.call(actor:, request_id: item.request_id)
          next Success(existing) if existing
          unless @event_store.read(@stream_factory.command(item.command_id), EventQueries::COMMAND_REGISTRATION).empty?
            raise InvalidCommandHistory, "Proposed batch-item Command ID is already in use"
          end
          payload = @registration_decider.call(item:)
          physical = @event_factory.build!(event: payload, event_id:,
            metadata: Metadata::CanonicalCommandV1.new(command_id: payload.command_id,
              actor_kind: actor.kind, actor_id: actor.id, recorded_by: "coordinator", policy_version: "operation-batch/v2",
              canonical_input_digest: item.canonical_input_digest),
            markers: [ "command:#{payload.command_id}", "tool:#{item.tool_name}", "operation-batch:#{command.batch_id}",
              "batch-item:#{command.batch_id}:#{item.index}", @request_marker.call(actor:, request_id: item.request_id) ], caused_by:)
          @event_store.append(@stream_factory.command(payload.command_id), [ physical ])
          Success(OperationBatches::RegistrationV1.new(payload:, canonical_input_digest: item.canonical_input_digest))
        end
      end
    end
  end
end
