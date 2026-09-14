# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteOperationBatchCommand < Dry::Operation
      def initialize(
        event_store:,
        loader: OperationBatches::Loader.new(event_store:),
        decider: OperationBatches::Decider.new,
        input_digest: CommandInputDigest.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        outcome_contract: Contracts::OperationBatchItemOutcome.new,
        command_loader: CommandLifecycle::Loader.new(event_store:),
        request_marker: CommandLifecycle::RequestMarker.new,
        target_builder: Tasks::TargetCommandBuilder.new,
        manifest_builder: OperationBatches::ManifestBuilder.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @input_digest = input_digest
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @outcome_contract = outcome_contract
        @command_loader = command_loader
        @request_marker = request_marker
        @target_builder = target_builder
        @manifest_builder = manifest_builder
      end

      def call_command(command, caused_by: nil)
        input_digest = @input_digest.call(command)
        domain_event_ids = allocate_domain_event_ids(command)
        correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
        allocations = item_allocations(command)

        steps do
          step @event_store.multiple {
            execute_attempt(
              command:,
              input_digest:,
              domain_event_ids:,
              correlation_id:,
              allocations:,
              caused_by:
            )
          }
        end
      end

      private

      def execute_attempt(command:, input_digest:, domain_event_ids:, correlation_id:, allocations:, caused_by:)
        snapshot = @loader.call(command.batch_id)
        verify_outcome!(snapshot.state, command) if command.is_a?(Commands::RecordOperationBatchItemOutcome)
        registrations = step registration_plans(command, state: snapshot.state, allocations:)
        decision = @decider.call(
          state: snapshot.state,
          command:,
          items: registrations.map(&:item)
        )
        return decision if decision.failure?

        domain_event = decision.value!.events.first
        batch_events = persist_domain(
          decision.value!,
          command:,
          event_ids: domain_event_ids,
          correlation_id:,
          input_digest:,
          caused_by:
        )
        persist_registrations(registrations, batch_events:)
        Success(
          build_completion(
            command:,
            event: domain_event,
            input_digest:,
            persisted_events: batch_events,
            completed_at: batch_events.last.created_at.utc.iso8601(6)
          )
        )
      end

      def registration_plans(command, state:, allocations:)
        return Success([]) unless command.is_a?(Commands::CreateOperationBatch)
        return Success([]) if state.creation

        plans = command.items.zip(allocations).map do |requested_item, allocation|
          plan = registration_plan(requested_item, allocation:)
          return plan if plan.failure?

          plan.value!
        end
        Success(plans)
      end

      def registration_plan(requested_item, allocation:)
        requested_command = @target_builder.call(requested_item.command_input)
        request_id = requested_command.command_id
        marker = @request_marker.call(actor: requested_command.actor, request_id:)
        existing_event = @event_store.read_global_marked(registration_criteria(marker)).first

        if existing_event
          existing = load(existing_event)
          existing_digest = existing_event.metadata.fetch("canonical_input_digest")
          unless existing.tool_name == requested_item.command_input.tool_name &&
                 existing_digest == requested_item.canonical_input_digest
            return Failure(request_reused(request_id:, existing:, existing_digest:, requested_item:))
          end
          command_id = existing.command_id
          register = false
        else
          command_id = allocation.command_id
          ensure_command_id_available!(command_id)
          register = true
        end

        document = requested_item.command_input.class.new(
          requested_item.command_input.attributes.merge(command_id:)
        )
        Success(
          OperationBatches::RegistrationPlanV2.new(
            item: OperationBatches::ItemV2.new(
              index: requested_item.index,
              request_id:,
              command_input: document,
              canonical_input_digest: requested_item.canonical_input_digest
            ),
            actor: requested_command.actor,
            register:,
            event_id: allocation.event_id
          )
        )
      end

      def verify_outcome!(state, command)
        item = state.item(command.index)
        return unless item

        command_snapshot = @command_loader.call(item.command_id)
        physical = command_snapshot.persisted_events.last
        result = @outcome_contract.call(
          command:,
          item:,
          command_state: command_snapshot.state,
          physical_target_event: physical
        )
        return if result.success?

        raise InvalidOperationBatchItemOutcome, result.errors.to_h.inspect
      end

      def persist_domain(plan, command:, event_ids:, correlation_id:, input_digest:, caused_by:)
        expected_stream = @stream_factory.operation_batch(command.batch_id)
        unless plan.writes.all? { _1.stream == expected_stream } && plan.writes.length == event_ids.length
          raise InvalidOperationBatchEventPlan, "Batch command must emit its complete plan to its own static stream"
        end

        events = plan.events.zip(event_ids).map do |event, event_id|
          @event_factory.build!(
            event:,
            event_id:,
            metadata: domain_metadata(command, event:, input_digest:),
            markers: markers(command, event:),
            caused_by:,
            correlation_id:
          )
        end
        @event_store.append(expected_stream, events)
      end

      def persist_registrations(plans, batch_events:)
        enqueued_by_index = batch_events.filter_map do |event|
          next unless event.type == "OperationBatchItemEnqueued"

          [ event.data.fetch("index"), event ]
        end.to_h
        plans.filter_map do |plan|
          next unless plan.register

          item = plan.item
          event = @event_factory.build!(
            event: Events::CommandRegisteredV1.new(
              command_id: item.command_id,
              request_id: item.request_id,
              tool_name: item.command_input.tool_name
            ),
            event_id: plan.event_id,
            metadata: Metadata::CanonicalCommandV1.new(
              command_id: item.command_id,
              actor_kind: plan.actor.kind,
              actor_id: plan.actor.id,
              recorded_by: "coordinator",
              policy_version: "operation-batch/v2",
              canonical_input_digest: item.canonical_input_digest
            ),
            markers: [
              "command:#{item.command_id}",
              "operation-batch:#{batch_events.first.stream.stream_id}",
              "batch-item:#{batch_events.first.stream.stream_id}:#{item.index}",
              "tool:#{item.command_input.tool_name}",
              @request_marker.call(actor: plan.actor, request_id: item.request_id)
            ],
            caused_by: enqueued_by_index.fetch(item.index)
          )
          @event_store.append(@stream_factory.command(item.command_id), [ event ]).sole
        end
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

      def item_allocations(command)
        return [] unless command.is_a?(Commands::CreateOperationBatch)

        command.items.map do
          OperationBatches::ItemAllocationV1.new(
            command_id: @id_generator.uuid_v7,
            event_id: @id_generator.uuid_v7
          )
        end
      end

      def allocate_domain_event_ids(command)
        count = case command
                when Commands::CreateOperationBatch then command.items.length + 2
                when Commands::RecordOperationBatchItemOutcome then 2
                else 1
                end
        Array.new(count) { @id_generator.uuid_v7 }
      end

      def domain_metadata(command, event:, input_digest:)
        common = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "operation-batch/v2"
        }
        return EventMetadata.new(common) unless command.is_a?(Commands::CreateOperationBatch)

        case event
        when Events::OperationBatchCreatedV2
          Metadata::OperationBatchCreationV2.new(
            **common,
            manifest_digest: command.manifest_digest,
            page_size: command.page_size
          )
        when Events::OperationBatchItemEnqueuedV1
          item = command.items.fetch(event.index)
          Metadata::OperationBatchItemV1.new(
            **common,
            canonical_input_digest: item.canonical_input_digest,
            encoded_byte_size: @manifest_builder.item_encoded_byte_size(event.input)
          )
        else
          EventMetadata.new(common)
        end
      end

      def markers(command, event:)
        values = [ "operation-batch:#{command.batch_id}", "command:#{command.command_id}" ]
        if event.respond_to?(:index)
          values << "batch-item:#{command.batch_id}:#{event.index}"
        end
        values
      end

      def registration_criteria(marker)
        GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl",
          stream_name: "Command",
          event_types: [ "CommandRegistered" ],
          markers: [ marker ],
          maximum_count: 1,
          direction: :asc
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def ensure_command_id_available!(command_id)
        return if @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_REGISTRATION
        ).empty?

        raise InvalidCommandHistory, "Generated batch-item Command ID is already in use"
      end

      def request_reused(request_id:, existing:, existing_digest:, requested_item:)
        OutcomeError.new(
          code: :command_id_reused,
          message: "Batch item request ID is already bound to another tool or input",
          details: {
            request_id:,
            existing_tool_name: existing.tool_name,
            existing_input_digest: existing_digest,
            requested_tool_name: requested_item.command_input.tool_name,
            requested_input_digest: requested_item.canonical_input_digest
          }
        )
      end
    end
  end
end
