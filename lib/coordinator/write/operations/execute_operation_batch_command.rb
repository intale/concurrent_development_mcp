# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteOperationBatchCommand < Dry::Operation
      def initialize(
        event_store:, loader: OperationBatches::Loader.new(event_store:),
        decider: OperationBatches::Decider.new, input_digest: CommandInputDigest.new,
        id_generator: IdGenerator.new, event_factory: EventFactory.new,
        stream_factory: StreamFactory.new, completion_builder: CommandResultBuilder.new,
        outcome_contract: Contracts::OperationBatchItemOutcome.new,
        command_loader: CommandLifecycle::Loader.new(event_store:),
        manifest_builder: OperationBatches::ManifestBuilder.new,
        revision_retry: OptimisticRevisionRetry.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @input_digest = input_digest
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @outcome_contract = outcome_contract
        @command_loader = command_loader
        @manifest_builder = manifest_builder
        @revision_retry = revision_retry
      end

      def prepare(command, caused_by: nil)
        items = if command.is_a?(Commands::CreateOperationBatch)
                  command.items.map do |item|
                    document = item.command_input.class.new(
                      item.command_input.attributes.merge(command_id: @id_generator.uuid_v7)
                    )
                    OperationBatches::ItemV2.new(
                      item.attributes.merge(command_input: document, request_id: item.command_input.command_id)
                    )
                  end
        else
                  []
        end
        count = case command
        when Commands::CreateOperationBatch then items.length + 5
        when Commands::RecordOperationBatchItemOutcome then 3
        when Commands::CompleteOperationBatch, Commands::CompleteOperationBatchCancellation then 2
        else 1
        end
        OperationBatches::PreparationV1.new(
          input_digest: @input_digest.call(command),
          domain_event_ids: Array.new(count) { @id_generator.uuid_v7 },
          correlation_id: caused_by&.correlation_id || @id_generator.uuid_v7,
          items:,
          item_encoded_byte_sizes: items.map { @manifest_builder.item_encoded_byte_size(_1.submitted_input) }
        )
      end

      def call_command(command, caused_by: nil)
        call_prepared_command(command, preparation: prepare(command, caused_by:), caused_by:)
      end

      def call_prepared_command(command, preparation:, caused_by: nil)
        steps do
          step @revision_retry.call { execute_attempt(command:, preparation:, caused_by:) }
        end
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(OutcomeError.new(code: :concurrency_conflict,
          message: "Batch changed concurrently; the request may succeed if retried",
          details: { command_id: command.command_id }))
      end

      private

      def execute_attempt(command:, preparation:, caused_by:)
        if command.is_a?(Commands::RequestOperationBatchContinuation)
          prior = @event_store.read_marked(@stream_factory.operation_batch(command.batch_id),
            MarkedEventReadCriteria.new(event_type: "OperationBatchContinuationRequested",
              marker: "command:#{command.command_id}", maximum_count: 1, direction: :asc)).first
          if prior
            payload = Events::OperationBatchContinuationRequestedV2.new(prior.data.deep_symbolize_keys)
            return Success(build_completion(command:, event: payload, input_digest: preparation.input_digest,
              persisted_events: [ prior ], completed_at: prior.created_at.utc.iso8601(6)))
          end
        end
        # Capture revision before state, so a concurrent fact never makes stale
        # selected state pass a newer optimistic lock.
        latest = @event_store.read_latest(@stream_factory.operation_batch(command.batch_id), EventQueries::OPERATION_BATCH_STREAM_REVISION)
        expected_revision = latest&.stream_revision || :no_stream
        snapshot = case command
        when Commands::CreateOperationBatch, Commands::CancelOperationBatch
                     @loader.control(command.batch_id)
        when Commands::RecordOperationBatchItemOutcome
                     @loader.item_identity(command.batch_id, command.index)
        else
                     @loader.call(command.batch_id)
        end
        decision = @decider.call(state: snapshot.state, command:, items: preparation.items)
        return decision if decision.failure?

        verify_outcome!(snapshot.state, command) if command.is_a?(Commands::RecordOperationBatchItemOutcome)
        batch_events = persist_domain(decision.value!, command:, preparation:, caused_by:, expected_revision:)
        Success(build_completion(
          command:, event: transition_event(command, decision.value!),
          input_digest: preparation.input_digest, persisted_events: batch_events,
          completed_at: batch_events.last.created_at.utc.iso8601(6)
        ))
      end

      def transition_event(command, plan)
        case command
        when Commands::CompleteOperationBatch, Commands::CompleteOperationBatchCancellation then plan.events.last
        else plan.events.first
        end
      end

      def verify_outcome!(state, command)
        item = state.item(command.index)
        command_snapshot = @command_loader.call(item.command_id)
        result = @outcome_contract.call(
          command:, item:, command_state: command_snapshot.state,
          physical_target_event: command_snapshot.persisted_events.last
        )
        return if result.success?

        raise InvalidOperationBatchItemOutcome, result.errors.to_h.inspect
      end

      def persist_domain(plan, command:, preparation:, caused_by:, expected_revision:)
        stream = @stream_factory.operation_batch(command.batch_id)
        unless plan.writes.all? { _1.stream == stream } && plan.writes.length == preparation.domain_event_ids.length
          raise InvalidOperationBatchEventPlan, "Batch command must emit its complete plan to its own static stream"
        end

        events = plan.events.zip(preparation.domain_event_ids).map do |event, event_id|
          @event_factory.build!(
            event:, event_id:,
            metadata: domain_metadata(command, event:, preparation:),
            markers: markers(command, event:), caused_by:,
            correlation_id: preparation.correlation_id
          )
        end
        @event_store.append(stream, events, expected_revision:)
      end

      def build_completion(command:, event:, input_digest:, persisted_events:, completed_at:)
        case command
        when Commands::CreateOperationBatch
          @completion_builder.operation_batch_create(command:, input_digest:, persisted_events:, completed_at:)
        when Commands::CancelOperationBatch
          @completion_builder.operation_batch_cancel(command:, input_digest:, persisted_events:, completed_at:)
        else
          @completion_builder.operation_batch_transition(command:, event:, input_digest:, persisted_events:, completed_at:)
        end
      end

      def domain_metadata(command, event:, preparation:)
        common = {
          command_id: command.command_id, actor_kind: command.actor.kind, actor_id: command.actor.id,
          recorded_by: "coordinator", policy_version: "operation-batch/v2"
        }
        return EventMetadata.new(common) unless command.is_a?(Commands::CreateOperationBatch)

        case event
        when Events::OperationBatchCreatedV2
          Metadata::OperationBatchCreationV2.new(**common, manifest_digest: command.manifest_digest, page_size: command.page_size)
        when Events::OperationBatchItemEnqueuedV1
          item = preparation.items.fetch(event.index)
          Metadata::OperationBatchItemV1.new(
            **common, canonical_input_digest: item.canonical_input_digest,
            encoded_byte_size: preparation.item_encoded_byte_sizes.fetch(event.index)
          )
        when Events::ProjectionNumbers::OperationBatchManifestAcceptedV1
          Metadata::OperationBatchManifestV1.new(**common, item_count: preparation.items.length,
            encoded_byte_size: preparation.item_encoded_byte_sizes.sum)
        else
          EventMetadata.new(common)
        end
      end

      def markers(command, event:)
        values = [ "operation-batch:#{command.batch_id}", "command:#{command.command_id}" ]
        values << "batch-item:#{command.batch_id}:#{event.index}" if event.respond_to?(:index)
        values
      end
    end
  end
end
