# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteOperationBatchCommand < Dry::Operation
      def initialize(
        event_store:,
        loader: OperationBatches::Loader.new(event_store:),
        decider: OperationBatches::Decider.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        outcome_contract: Contracts::OperationBatchItemOutcome.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @outcome_contract = outcome_contract
      end

      def call_command(command, caused_by: nil)
        input_digest = @input_digest.call(command)
        domain_event_id = @id_generator.uuid_v7
        completion_event_id = @id_generator.uuid_v7
        occurred_at = logical_time(command) || @clock.now

        steps do
          step @event_store.multiple {
            execute_attempt(
              command:,
              input_digest:,
              domain_event_id:,
              completion_event_id:,
              occurred_at:,
              caused_by:
            )
          }
        end
      end

      private

      def execute_attempt(command:, input_digest:, domain_event_id:, completion_event_id:, occurred_at:, caused_by:)
        replay = replay_result(command:, input_digest:)
        return replay if replay

        snapshot = @loader.call(command.batch_id)
        verify_outcome!(snapshot.state, command) if command.is_a?(Commands::RecordOperationBatchItemOutcome)
        decision = @decider.call(state: snapshot.state, command:, occurred_at:)
        return decision if decision.failure?

        domain_event = decision.value!.events.sole
        persisted = persist_domain(
          decision.value!,
          command:,
          event_id: domain_event_id,
          caused_by:
        )
        completion = build_completion(
          command:,
          event: domain_event,
          input_digest:,
          persisted_events: persisted,
          completed_at: occurred_at
        )
        persist_completion(
          completion,
          command:,
          event_id: completion_event_id,
          caused_by:
        )
        Success(completion)
      end

      def verify_outcome!(state, command)
        item = state.item(command.index)
        return unless item

        physical, completion = load_target_completion(command.target_completion)
        result = @outcome_contract.call(
          command:,
          item:,
          completion:,
          physical_completion: physical
        )
        return if result.success?

        raise InvalidOperationBatchItemOutcome, result.errors.to_h.inspect
      end

      def load_target_completion(reference)
        return [ nil, nil ] unless reference

        stream = StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
        physical = @event_store.read_at(stream, reference.stream_revision)
        return [ nil, nil ] unless physical

        completion = @schema_registry.load(
          type: physical.type,
          schema_version: physical.metadata.fetch("schema_version"),
          data: physical.data
        )
        [ physical, completion ]
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion

        requested_tool = @input_digest.document(command).tool_name
        if completion.tool_name == requested_tool && completion.canonical_input_digest == input_digest
          Success(completion)
        else
          Failure(
            OutcomeError.new(
              code: :command_id_reused,
              message: "Command ID is already bound to another tool or input",
              details: {
                command_id: command.command_id,
                existing_tool_name: completion.tool_name,
                existing_input_digest: completion.canonical_input_digest,
                requested_tool_name: requested_tool,
                requested_input_digest: input_digest
              }
            )
          )
        end
      end

      def load_completion(command_id)
        event = @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_COMPLETION
        ).first
        return unless event

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain(plan, command:, event_id:, caused_by:)
        expected_stream = @stream_factory.operation_batch(command.batch_id)
        unless plan.writes.length == 1 && plan.writes.first.stream == expected_stream
          raise InvalidOperationBatchEventPlan, "Batch command must emit once to its own static stream"
        end

        event = @event_factory.build!(
          event: plan.events.sole,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "operation-batch:#{command.batch_id}", "command:#{command.command_id}" ],
          caused_by:
        )
        @event_store.append(expected_stream, [ event ])
      end

      def persist_completion(completion, command:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}", "operation-batch:#{command.batch_id}" ],
          caused_by:
        )
        @event_store.append(@stream_factory.command(command.command_id), [ event ])
      end

      def build_completion(command:, event:, input_digest:, persisted_events:, completed_at:)
        case command
        when Commands::CreateOperationBatch
          @completion_builder.operation_batch_create(
            command:,
            input_digest:,
            persisted_events:,
            completed_at:
          )
        when Commands::CancelOperationBatch
          @completion_builder.operation_batch_cancel(
            command:,
            input_digest:,
            persisted_events:,
            completed_at:
          )
        else
          @completion_builder.operation_batch_transition(
            command:,
            event:,
            input_digest:,
            persisted_events:,
            completed_at:
          )
        end
      end

      def logical_time(command)
        case command
        when Commands::CreateOperationBatch, Commands::CancelOperationBatch then nil
        when Commands::RecordOperationBatchItemOutcome then command.finished_at
        when Commands::RequestOperationBatchContinuation then command.requested_at
        when Commands::CompleteOperationBatch then command.completed_at
        when Commands::CompleteOperationBatchCancellation then command.cancelled_at
        end
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "operation-batch/v1"
        )
      end
    end
  end
end
