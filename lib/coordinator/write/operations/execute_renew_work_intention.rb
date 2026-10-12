# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRenewWorkIntention
      include Dry::Monads[:result]

      def initialize(event_store:, renewal_loader: WorkIntentionRenewals::Loader.new(event_store:),
        intention_loader: WorkIntentionLoader.new(event_store:), decider: WorkIntentionRenewals::RenewMember.new,
        stream_factory: StreamFactory.new, event_factory: EventFactory.new, id_generator: IdGenerator.new,
        clock: SystemClock.new, resource_loader: WorkIntentionResourceLoader.new(event_store:),
        registration_loader: RepositoryRegistrationLoader.new(event_store:), marker_builder: RepositoryMarkerBuilder.new,
        revision_retry: OptimisticRevisionRetry.new)
        @event_store, @renewal_loader, @intention_loader = event_store, renewal_loader, intention_loader
        @decider, @stream_factory, @event_factory = decider, stream_factory, event_factory
        @id_generator, @clock, @resource_loader = id_generator, clock, resource_loader
        @registration_loader, @marker_builder, @revision_retry = registration_loader, marker_builder, revision_retry
      end

      def call_command(command, caused_by:)
        event_id = @id_generator.uuid_v7
        @revision_retry.call do
          # Exact child replay precedes liveness: later withdrawal cannot erase a committed success.
          prior = @event_store.read_marked(@stream_factory.resource_work_intention(command.intention_id),
            MarkedEventReadCriteria.new(event_type: "ResourceWorkIntentionRenewed",
              marker: "command:#{command.command_id}", maximum_count: 1, direction: :asc)).first
          next Success(prior) if prior

          renewal = @renewal_loader.call(command.renewal_id).state
          next Failure(OutcomeError.new(code: :command_terminal, message: "Renewal Saga is already terminal",
            details: { command_id: command.command_id })) if renewal.terminal
          snapshot = @intention_loader.call(command.intention_id)
          assignment = renewal.assignments.find { _1.intention_id == command.intention_id }
          decision = @decider.call(state: snapshot.state, assignment:, request: renewal.request, command:, now: @clock.now)
          next decision if decision.failure?
          next Success(nil) unless decision.value!

          resource = @resource_loader.call(WorkIntentionTargetV1.new(resource_id: command.resource_id,
            base_blob_oid: snapshot.state.base_blob_oid), repository_id: snapshot.state.repository_id)
          next resource if resource.failure?
          registration = @registration_loader.call(snapshot.state.repository_id)
          next Failure(OutcomeError.new(code: :repository_not_registered, message: "Repository is not registered",
            details: { repository_id: snapshot.state.repository_id })) unless registration

          physical = @event_factory.build!(event: decision.value!, event_id:,
            metadata: WorkIntentionRenewals::ChildMetadata.new(command_id: command.command_id,
              actor_kind: command.actor.kind, actor_id: command.actor.id, recorded_by: "coordinator",
              policy_version: WorkIntentionPolicyV1::VERSION, renewal_id: command.renewal_id),
            markers: [ "command:#{command.command_id}", "renewal:#{command.renewal_id}",
              "change-set:#{command.change_set_id}", "work-item:#{command.work_item_id}", "attempt:#{command.attempt_id}",
              "work-intention-set:#{command.intention_set_id}", "work-intention:#{command.intention_id}",
              "resource:#{command.resource_id}", "resource-kind:#{resource.value!.kind}",
              *@marker_builder.call(registration),
              *@marker_builder.work_intention_event_markers(repository_id: snapshot.state.repository_id, resource_path: resource.value!.path) ],
            caused_by:)
          Success(@event_store.append(@stream_factory.resource_work_intention(command.intention_id),
            [ physical ], expected_revision: snapshot.stream_revision).sole)
        end
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(OutcomeError.new(code: :concurrency_conflict,
          message: "Renewal member changed concurrently after three attempts; the request may succeed if retried",
          details: { command_id: command.command_id }))
      end
    end
  end
end
