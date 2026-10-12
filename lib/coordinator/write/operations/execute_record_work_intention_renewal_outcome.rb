# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordWorkIntentionRenewalOutcome
      include Dry::Monads[:result]

      def initialize(event_store:, loader: WorkIntentionRenewals::Loader.new(event_store:),
        decider: WorkIntentionRenewals::RecordOutcome.new, stream_factory: StreamFactory.new,
        event_factory: EventFactory.new, id_generator: IdGenerator.new, revision_retry: OptimisticRevisionRetry.new)
        @event_store, @loader, @decider = event_store, loader, decider
        @stream_factory, @event_factory, @id_generator = stream_factory, event_factory, id_generator
        @revision_retry = revision_retry
      end

      def call_command(command, caused_by:)
        event_ids = Array.new(2) { @id_generator.uuid_v7 }
        @revision_retry.call do
          snapshot = @loader.call(command.renewal_id)
          decision = @decider.call(state: snapshot.state, command:)
          next decision if decision.failure?
          next Success(snapshot.events.last) if decision.value!.empty?

          verify_reference!(command, snapshot.state) if command.renewal_event
          events = decision.value!.each_with_index.map do |payload, index|
            @event_factory.build!(event: payload, event_id: event_ids.fetch(index),
              metadata: WorkIntentionRenewals::ChildMetadata.new(command_id: command.command_id,
                actor_kind: command.actor.kind, actor_id: command.actor.id, recorded_by: "coordinator",
                policy_version: "work-intention-renewal/v1", renewal_id: command.renewal_id),
              markers: [ "renewal:#{command.renewal_id}", "command:#{command.command_id}",
                "work-intention-set:#{snapshot.state.request.intention_set_id}" ], caused_by:)
          end
          Success(@event_store.append(@stream_factory.work_intention_set_renewal(command.renewal_id),
            events, expected_revision: snapshot.latest_revision).last)
        end
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(OutcomeError.new(code: :concurrency_conflict,
          message: "Renewal outcome changed concurrently after three attempts; retry delivery",
          details: { command_id: command.command_id }))
      end

      private

      def verify_reference!(command, state)
        assignment = state.assignments.find { _1.intention_id == command.intention_id }
        reference = command.renewal_event
        physical = @event_store.read(@stream_factory.resource_work_intention(command.intention_id),
          EventReadCriteria.new(event_types: [ "ResourceWorkIntentionRenewed" ], maximum_count: 1,
            direction: :asc, from_revision: reference.stream_revision, to_revision: reference.stream_revision)).first
        exact = physical && physical.id == reference.event_id && physical.type == reference.type &&
          physical.stream.context == reference.stream_context && physical.stream.stream_name == reference.stream_name &&
          physical.stream.stream_id == reference.stream_id &&
          physical.metadata.fetch("command_id") == assignment.renew_command_id &&
          physical.metadata.fetch("renewal_id") == command.renewal_id
        raise InvalidCommandHistory, "Renewal outcome does not reference its assigned child effect" unless exact
      end
    end
  end
end
