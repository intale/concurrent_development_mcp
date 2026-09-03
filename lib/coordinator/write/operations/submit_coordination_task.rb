# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class SubmitCoordinationTask
      include Dry::Monads[:result]

      POLL_INTERVAL_MS = 500

      def initialize(
        event_store:,
        decider: Domain::CoordinationTasks::Submit.new,
        input_digest: CommandInputDigest.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        request_marker: CommandLifecycle::RequestMarker.new,
        execution_lane: Tasks::ExecutionLane.new,
        correlation_resolver: Tasks::CorrelationResolver.new(
          release_set_correlation_loader: ReleaseSets::CorrelationLoader.new(event_store:)
        )
      )
        @event_store = event_store
        @decider = decider
        @input_digest = input_digest
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @request_marker = request_marker
        @execution_lane = execution_lane
        @correlation_resolver = correlation_resolver
      end

      def call(target_command)
        request_id = target_command.command_id
        canonical_input_digest = @input_digest.request(target_command)
        command_id = @id_generator.uuid_v7
        task_id = @id_generator.uuid_v7
        command_event_id = @id_generator.uuid_v7
        task_event_id = @id_generator.uuid_v7
        correlation_id = @correlation_resolver.call(target_command)
        rebound_command = target_command.class.new(target_command.attributes.merge(command_id:))
        command_input = @input_digest.document(rebound_command)
        command = Commands::SubmitCoordinationTask.new(
          task_id:,
          request_id:,
          tool_name: command_input.tool_name,
          command_id:,
          command_input:,
          canonical_input_digest:,
          ttl_ms: nil,
          poll_interval_ms: POLL_INTERVAL_MS
        )

        @event_store.multiple do
          existing = existing_submission(
            target_command.actor,
            request_id:,
            canonical_input_digest:,
            tool_name: command.tool_name
          )
          next existing if existing

          collision = generated_identity_collision(command)
          next collision if collision

          events = @decider.call(
            state: Domain::CoordinationTasks::State.initial,
            command:
          ).value!
          persisted = append(
            events:,
            command:,
            actor: target_command.actor,
            command_event_id:,
            task_event_id:,
            correlation_id:
          )
          Success(
            Domain::CoordinationTasks::State.reduce(
              [ events.fetch(1) ],
              occurred_at: [ persisted.fetch(1).created_at.utc.iso8601(6) ]
            )
          )
        end
      end

      private

      def existing_submission(actor, request_id:, canonical_input_digest:, tool_name:)
        registration_event = @event_store.read_global_marked(
          request_registration_criteria(request_marker(actor, request_id))
        ).first
        return unless registration_event

        registration = load(registration_event)
        existing_digest = registration_event.metadata.fetch("canonical_input_digest")
        unless registration.tool_name == tool_name && existing_digest == canonical_input_digest
          return Failure(request_reused(
            request_id:,
            existing_tool_name: registration.tool_name,
            existing_input_digest: existing_digest,
            requested_tool_name: tool_name,
            requested_input_digest: canonical_input_digest
          ))
        end

        task_event = @event_store.read_global_marked(task_submission_criteria(registration.command_id)).first
        return Failure(incomplete_submission(registration.command_id)) unless task_event

        payload = load(task_event)
        Success(
          Domain::CoordinationTasks::State.reduce(
            [ payload ],
            occurred_at: [ task_event.created_at.utc.iso8601(6) ]
          )
        )
      end

      def generated_identity_collision(command)
        command_exists = @event_store.read(
          @stream_factory.command(command.command_id),
          EventQueries::COMMAND_REGISTRATION
        ).any?
        task_exists = @event_store.read(
          @stream_factory.coordination_task(command.task_id),
          EventQueries::COORDINATION_TASK_HISTORY
        ).any?
        return unless command_exists || task_exists

        Failure(concurrency_conflict(command.task_id))
      end

      def append(events:, command:, actor:, command_event_id:, task_event_id:, correlation_id:)
        metadata = Metadata::CanonicalCommandV1.new(
          command_id: command.command_id,
          actor_kind: actor.kind,
          actor_id: actor.id,
          recorded_by: "coordinator",
          policy_version: "coordination-task/v3",
          canonical_input_digest: command.canonical_input_digest
        )
        registration_marker = request_marker(actor, command.request_id)
        command_event = @event_factory.build!(
          event: events.fetch(0),
          event_id: command_event_id,
          metadata:,
          markers: [
            "command:#{command.command_id}",
            "task:#{command.task_id}",
            registration_marker
          ],
          correlation_id:
        )
        persisted_command = @event_store.append(
          @stream_factory.command(command.command_id),
          [ command_event ]
        ).sole
        task_event = @event_factory.build!(
          event: events.fetch(1),
          event_id: task_event_id,
          metadata: Metadata::CanonicalCommandV1.new(
            command_id: command.command_id,
            actor_kind: actor.kind,
            actor_id: actor.id,
            recorded_by: "coordinator",
            policy_version: "coordination-task/v3",
            canonical_input_digest: command.canonical_input_digest
          ),
          markers: [
            "task:#{command.task_id}",
            "command:#{command.command_id}",
            registration_marker,
            @execution_lane.marker(command.task_id),
            "tool:#{command.tool_name}"
          ],
          caused_by: persisted_command,
          correlation_id:
        )
        persisted_task = @event_store.append(
          @stream_factory.coordination_task(command.task_id),
          [ task_event ]
        ).sole

        [ persisted_command, persisted_task ]
      end

      def request_marker(actor, request_id)
        @request_marker.call(actor:, request_id:)
      end

      def request_registration_criteria(marker)
        GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl",
          stream_name: "Command",
          event_types: [ "CommandRegistered" ],
          markers: [ marker ],
          maximum_count: 1,
          direction: :asc
        )
      end

      def task_submission_criteria(command_id)
        GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl",
          stream_name: "CoordinationTask",
          event_types: [ "CoordinationTaskSubmitted" ],
          markers: [ "command:#{command_id}" ],
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

      def request_reused(request_id:, **details)
        OutcomeError.new(
          code: :command_id_reused,
          message: "Request ID is already bound to another tool or input",
          details: { request_id: }.merge(details)
        )
      end

      def incomplete_submission(command_id)
        Tasks::LifecycleError.new(
          code: :concurrency_conflict,
          message: "Registered Command has no Task; the request may succeed if retried",
          task_id: command_id
        )
      end

      def concurrency_conflict(task_id)
        Tasks::LifecycleError.new(
          code: :concurrency_conflict,
          message: "Could not allocate a Task ID; the request may succeed if retried",
          task_id:
        )
      end
    end
  end
end
