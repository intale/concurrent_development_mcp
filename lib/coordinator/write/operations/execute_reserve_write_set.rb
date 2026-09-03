# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteReserveWriteSet < Dry::Operation
      TOOL_NAME = "write_set_reserve"

      def initialize(
        event_store:,
        preparer: PrepareReserveWriteSet.new,
        decider: Domain::ResourceLeases::Reserve.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        lease_resource_loader: LeaseResourceLoader.new(event_store:),
        event_plan_contract: Contracts::WriteSetReservationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @repository_registration_loader = repository_registration_loader
        @repository_marker_builder = repository_marker_builder
        @lease_resource_loader = lease_resource_loader
        @resource_boundary_loader = ResourceBoundaryLoader.new(event_store:, schema_registry:)
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        prepared = prepare_logical_values(command)
        steps do
          step @event_store.multiple { execute_scoped_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        acquired_at = @clock.now
        expires_at = (Time.iso8601(acquired_at) + command.lease_duration_seconds).utc.iso8601(6)

        PreparedWriteSetReservation.new(
          acquired_at:,
          expires_at:,
          input_digest: @input_digest.write_set_reserve(command),
          lease_set_id: @id_generator.uuid_v7,
          resources: command.resources.map do |resource|
            PreparedLeaseTargetV1.new(
              target: resource,
              lease_id: @id_generator.uuid_v7,
              event_id: @id_generator.uuid_v7
            )
          end,
          reservation_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_scoped_attempt(command:, prepared:, caused_by:)
        registration = @repository_registration_loader.call(command.repository_id)
        return repository_not_registered(command) unless registration

        resources = load_resources(command)
        return resources if resources.failure?

        execute_attempt(
          command:,
          resources: resources.value!,
          prepared:,
          repository_registration: registration,
          caused_by:
        )
      end

      def execute_attempt(command:, resources:, prepared:, repository_registration:, caused_by:)
        attempt_state = load_attempt_state(command.attempt_id)
        lease_states = resources.map { load_lease_state(_1.resource_id) }
        boundary_states = load_boundary_states(command, resources:)
        return boundary_states if boundary_states.failure?

        decision = @decider.call(
          attempt_state:,
          lease_states: lease_states + boundary_states.value!,
          command:,
          resources:,
          lease_set_id: prepared.lease_set_id,
          lease_ids: prepared.resources.map(&:lease_id),
          acquired_at: prepared.acquired_at,
          expires_at: prepared.expires_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, command:, resources:, prepared:, lease_states:)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: TOOL_NAME,
          command_id: command.command_id
        )
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: "resource_boundary_dcb",
          command_id: command.command_id,
          event_ids: prepared.resources.map(&:event_id)
        )
        persisted_domain_events = persist_domain_plan(
          plan,
          command:,
          prepared:,
          repository_registration:,
          caused_by:
        )
        reservation = plan.events.last
        completion = @completion_builder.write_set_reserve(
          command:,
          reservation:,
          input_digest: prepared.input_digest,
          persisted_events: persisted_domain_events,
          completed_at: prepared.acquired_at
        )

        Success(completion)
      end

      def load_attempt_state(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          EventQueries::ATTEMPT_FOR_WRITE_SET_RESERVATION
        ).map { load_event(_1) }

        Domain::Attempts::State.reduce(events)
      end

      def load_lease_state(resource_id)
        events = @event_store.read_grouped(
          @stream_factory.resource_lease(resource_id),
          EventQueries::RESOURCE_LEASE_FOR_RESERVATION
        ).reverse.map { load_event(_1) }

        Domain::ResourceLeases::State.reduce(events)
      end

      def load_boundary_states(command, resources:)
        markers = resources.flat_map do |resource|
          @repository_marker_builder.resource_boundary_markers(
            repository_id: command.repository_id,
            resource_kind: resource.kind,
            resource_path: resource.path
          )
        end.uniq
        Success(@resource_boundary_loader.call(markers, repository_id: command.repository_id).states)
      rescue EventHistoryLimitExceeded
        Failure(
          OutcomeError.new(
            code: :resource_boundary_maintenance_required,
            message: "Resource boundary maintenance is catching up; retry this request",
            details: {
              repository_id: command.repository_id,
              boundary_marker_count: markers.length,
              maximum_delta_event_count: EventQueries::RESOURCE_BOUNDARY_DECISION_DELTA_MAXIMUM_COUNT
            }
          )
        )
      end

      def load_resources(command)
        resources = command.resources.map do |target|
          result = @lease_resource_loader.call(target, repository_id: command.repository_id)
          return result if result.failure?

          result.value!
        end

        Success(resources)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_event_plan!(plan, command:, resources:, prepared:, lease_states:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          resources:,
          attempt_stream: @stream_factory.attempt(command.attempt_id),
          lease_states:,
          lease_set_id: prepared.lease_set_id,
          lease_ids: prepared.resources.map(&:lease_id),
          acquired_at: prepared.acquired_at,
          expires_at: prepared.expires_at
        )
        return if result.success?

        raise InvalidWriteSetReservationEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, command:, prepared:, repository_registration:, caused_by:)
        event_ids = prepared.resources.map(&:event_id) + [ prepared.reservation_event_id ]

        plan.writes.zip(event_ids).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: command_metadata(command),
            markers: event_markers(command, write.event, repository_registration:),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def event_markers(command, event, repository_registration:)
        common = [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "command:#{command.command_id}"
        ] + @repository_marker_builder.call(repository_registration)
        return common + [ "lease-set:#{event.lease_set_id}" ] unless event.is_a?(Events::ResourceLeaseAcquiredV2)

        common + [
          "lease-set:#{event.lease_set_id}",
          "resource:#{event.resource_id}",
          "resource-kind:#{event.resource_kind}",
          *@repository_marker_builder.resource_event_markers(
            repository_id: event.repository_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path
          )
        ]
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: LeaseResourceV2::POLICY_VERSION
        )
      end

      def repository_not_registered(command)
        Failure(
          OutcomeError.new(
            code: :repository_not_registered,
            message: "Repository is not registered",
            details: { repository_id: command.repository_id }
          )
        )
      end
    end
  end
end
