# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteExpandWriteSet < Dry::Operation
      TOOL_NAME = "write_set_expand"

      def initialize(
        event_store:,
        preparer: PrepareExpandWriteSet.new,
        decider: Domain::ResourceLeases::Expand.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        lease_resource_loader: LeaseResourceLoader.new(event_store:),
        event_plan_contract: Contracts::WriteSetExpansionEventPlan.new
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
        PreparedWriteSetExpansion.new(
          expanded_at: @clock.now,
          input_digest: @input_digest.write_set_expand(command),
          resources: command.resources.map do |resource|
            PreparedLeaseTargetV1.new(
              target: resource,
              lease_id: @id_generator.uuid_v7,
              event_id: @id_generator.uuid_v7
            )
          end,
          expansion_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
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
        replay = replay_result(command:, input_digest: prepared.input_digest)
        return replay if replay

        attempt_state = load_attempt_state(command.attempt_id)
        states = load_resource_states(attempt_state:, resources:)
        current_observations = current_observations(attempt_state:, states:)
        requested_observations = requested_observations(prepared:, resources:, states:)
        boundary_states = load_boundary_states(command, resources:)
        return boundary_states if boundary_states.failure?

        decision = @decider.call(
          attempt_state:,
          current_observations:,
          requested_observations:,
          boundary_states: boundary_states.value!,
          command:,
          expanded_at: prepared.expanded_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan,
          command:,
          attempt_state:,
          requested_observations:,
          expanded_at: prepared.expanded_at
        )
        persisted_domain_events = persist_domain_plan(
          plan,
          command:,
          prepared:,
          repository_registration:,
          caused_by:
        )
        expansion = plan.events.last
        completion = @completion_builder.write_set_expand(
          command:,
          expansion:,
          input_digest: prepared.input_digest,
          persisted_events: persisted_domain_events,
          completed_at: prepared.expanded_at
        )
        persist_completion(
          completion,
          command:,
          event_id: prepared.completion_event_id,
          caused_by:
        )

        Success(completion)
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion

        if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest
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
                requested_tool_name: TOOL_NAME,
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

        load_event(event)
      end

      def load_attempt_state(attempt_id)
        stream = @stream_factory.attempt(attempt_id)
        membership = @event_store.read(
          stream,
          EventQueries::ATTEMPT_FOR_WRITE_SET_EXPANSION
        )
        lifecycle = @event_store.read_grouped(
          stream,
          EventQueries::ATTEMPT_LATEST_WRITE_SET_LIFECYCLE
        )
        events = SpecificStreamEventSequence.merge(membership, lifecycle.reverse)

        Domain::Attempts::State.reduce(events.map { load_event(_1) })
      end

      def load_resource_states(attempt_state:, resources:)
        resource_ids = (
          attempt_state.lease_resources.map(&:resource_id) + resources.map(&:resource_id)
        ).uniq.sort_by(&:b)

        resource_ids.to_h { [ _1, load_lease_state(_1) ] }
      end

      def load_lease_state(resource_id)
        events = @event_store.read_grouped(
          @stream_factory.resource_lease(resource_id),
          EventQueries::RESOURCE_LEASE_FOR_RESERVATION
        ).reverse.map { load_event(_1) }

        Domain::ResourceLeases::State.reduce(events)
      end

      def current_observations(attempt_state:, states:)
        attempt_state.lease_resources.map do |reference|
          CurrentLeaseObservationV2.new(
            reference:,
            state: states.fetch(reference.resource_id)
          )
        end
      end

      def requested_observations(prepared:, resources:, states:)
        resources.map do |resource|
          prepared_target = prepared.resources.find { _1.target.resource_id == resource.resource_id }
          RequestedLeaseObservationV2.new(
            prepared_target:,
            resource:,
            state: states.fetch(resource.resource_id)
          )
        end
      end

      def load_boundary_states(command, resources:)
        markers = resources.flat_map do |resource|
          @repository_marker_builder.resource_boundary_markers(
            repository_id: command.repository_id,
            resource_kind: resource.kind,
            resource_path: resource.path
          )
        end.uniq
        Success(@resource_boundary_loader.call(markers).states)
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

      def verify_event_plan!(plan, command:, attempt_state:, requested_observations:, expanded_at:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          attempt_state:,
          requested_observations:,
          expanded_at:
        )
        return if result.success?

        raise InvalidWriteSetExpansionEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, command:, prepared:, repository_registration:, caused_by:)
        plan.writes.map do |write|
          event = @event_factory.build!(
            event: write.event,
            event_id: event_id_for(write.event, prepared:),
            metadata: command_metadata(command),
            markers: event_markers(command, write.event, repository_registration:),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def event_id_for(event, prepared:)
        return prepared.expansion_event_id if event.is_a?(Events::WriteSetExpandedV2)

        prepared.resources.find do |candidate|
          candidate.target.resource_id == event.resource_id
        end.event_id
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

      def persist_completion(completion, command:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )

        @event_store.append(@stream_factory.command(command.command_id), [ event ])
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
