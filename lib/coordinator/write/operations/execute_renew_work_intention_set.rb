# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRenewWorkIntentionSet < Dry::Operation
      def initialize(event_store:,
        decider: WorkIntentionRenewals::ValidateRequest.new, clock: SystemClock.new, id_generator: IdGenerator.new,
        event_factory: EventFactory.new, schema_registry: EventSchemaRegistry.new, stream_factory: StreamFactory.new,
        set_loader: WorkIntentionSetLoader.new(event_store:), intention_loader: WorkIntentionLoader.new(event_store:),
        renewal_loader: WorkIntentionRenewals::Loader.new(event_store:), request_decider: WorkIntentionRenewals::Request.new,
        revision_retry: OptimisticRevisionRetry.new)
        @event_store, @decider = event_store, decider
        @clock, @id_generator, @event_factory = clock, id_generator, event_factory
        @schema_registry, @stream_factory, @set_loader = schema_registry, stream_factory, set_loader
        @intention_loader, @renewal_loader, @request_decider = intention_loader, renewal_loader, request_decider
        @revision_retry = revision_retry
      end

      def call_command(command, caused_by: nil)
        requested_at = @clock.now
        expires_at = (Time.iso8601(requested_at) + command.ttl_seconds).utc.iso8601(6)
        assignments = command.intentions.each_with_index.map do |reference, position|
          Events::OptimisticSagas::WorkIntentionRenewalAssignedV1.new(
            renewal_id: command.command_id, position:, **reference.to_h,
            renew_command_id: @id_generator.uuid_v7, outcome_command_id: @id_generator.uuid_v7)
        end
        event_ids = Array.new(assignments.length + 1) { @id_generator.uuid_v7 }
        correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
        @revision_retry.call do
          snapshot = @renewal_loader.call(command.command_id)
          next Success(snapshot.events.first) if snapshot.state.request

          attempt = @event_store.read(@stream_factory.attempt(command.attempt_id), EventQueries::ATTEMPT_FOR_WORK_INTENTIONS)
          attempt_state = Domain::Attempts::State.reduce(attempt.map { load_event(_1) })
          set_state = @set_loader.call(command.intention_set_id)
          member_states = set_state.members.map { @intention_loader.call(_1.intention_id).state }
          validation = @decider.call(attempt_state:, set_state:, member_states:, command:,
            renewed_at: requested_at)
          next validation if validation.failure?

          events = @request_decider.call(command:, expires_at:, assignments:).zip(event_ids).map do |payload, event_id|
            @event_factory.build!(event: payload, event_id:,
              metadata: WorkIntentionRenewals::RequestMetadata.new(command_id: command.command_id, actor_kind: command.actor.kind,
                actor_id: command.actor.id, recorded_by: "coordinator", policy_version: "work-intention-renewal/v1",
                task_id: caused_by&.data&.fetch("task_id", nil)),
              markers: [ "command:#{command.command_id}", "renewal:#{command.command_id}",
                "work-intention-set:#{command.intention_set_id}", "attempt:#{command.attempt_id}" ], caused_by:, correlation_id:)
          end
          persisted = @event_store.append(@stream_factory.work_intention_set_renewal(command.command_id),
            events, expected_revision: snapshot.latest_revision)
          Success(persisted.first)
        end
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(OutcomeError.new(code: :concurrency_conflict,
          message: "Renewal request changed concurrently; the request may succeed if retried",
          details: { command_id: command.command_id }))
      end

      private

      def load_event(event)
        @schema_registry.load(type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data)
      end
    end
  end
end
