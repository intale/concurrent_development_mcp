# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteSubmitCandidate < Dry::Operation
      TOOL_NAME = "candidate_submit"

      def initialize(
        event_store:,
        preparer: PrepareSubmitCandidate.new,
        decider: Domain::Candidates::Submit.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        head_identity_builder: Candidates::HeadIdentityBuilder.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        event_plan_contract: Contracts::CandidateSubmissionEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @head_identity_builder = head_identity_builder
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @repository_registration_loader = repository_registration_loader
        @repository_marker_builder = repository_marker_builder
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
        PreparedCandidateSubmission.new(
          submitted_at: @clock.now,
          input_digest: @input_digest.candidate_submit(command),
          head_identity: @head_identity_builder.call(
            repository_id: command.repository_id,
            object_format: command.object_format,
            head_commit_oid: command.head_commit_oid
          ),
          candidate_event_id: @id_generator.uuid_v7,
          manifest_event_id: @id_generator.uuid_v7,
          build_context_event_id: command.build_context && @id_generator.uuid_v7,
          head_registration_event_id: @id_generator.uuid_v7,
          attachment_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_scoped_attempt(command:, prepared:, caused_by:)
        registration = @repository_registration_loader.call(command.repository_id)
        return repository_not_registered(command) unless registration

        execute_attempt(
          command:,
          prepared:,
          repository_registration: registration,
          caused_by:
        )
      end

      def execute_attempt(command:, prepared:, repository_registration:, caused_by:)
        replay = replay_result(command:, input_digest: prepared.input_digest)
        return replay if replay

        state_result = load_submission_state(command, prepared.head_identity)
        return state_result if state_result.failure?

        state = state_result.value!
        candidate_event = future_candidate_reference(command, prepared.candidate_event_id)
        decision = @decider.call(
          state:,
          command:,
          submitted_at: prepared.submitted_at,
          candidate_event:,
          head_identity: prepared.head_identity
        )
        return decision if decision.failure?

        plan = apply_event_plan_contract(
          decision.value!,
          state:,
          command:,
          prepared:,
          candidate_event:
        )
        persisted_events = persist_domain_plan(
          plan,
          command:,
          prepared:,
          repository_registration:,
          caused_by:
        )
        submission = plan.events.fetch(0)
        completion = @completion_builder.candidate_submit(
          command:,
          submission:,
          input_digest: prepared.input_digest,
          persisted_events:,
          completed_at: prepared.submitted_at
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
        event && load_event(event)
      end

      def load_submission_state(command, head_identity)
        attempt = load_attempt_state(command.attempt_id)
        unless attempt.lease_policy_version.nil? || attempt.lease_policy_version == LeaseResourceV2::POLICY_VERSION
          return Failure(
            OutcomeError.new(
              code: :resource_identity_policy_mismatch,
              message: "The current write set predates Resource UUID leases and must be reacquired",
              details: {
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id,
                attempt_id: command.attempt_id,
                current_policy_version: attempt.lease_policy_version,
                requested_policy_version: LeaseResourceV2::POLICY_VERSION
              }
            )
          )
        end
        current_leases = attempt.lease_resources.map do |reference|
          CurrentLeaseObservationV2.new(
            reference:,
            state: load_lease_state(reference.resource_id)
          )
        end

        Success(Domain::Candidates::SubmissionState.new(
          existing_candidate: load_existing_reference(
            @stream_factory.candidate(command.candidate_id),
            EventQueries::CANDIDATE_EXISTENCE
          ),
          existing_head: load_existing_reference(
            @stream_factory.candidate_head(head_identity.registry_id),
            EventQueries::CANDIDATE_HEAD_REGISTRATION
          ),
          attempt:,
          current_leases:
        ))
      end

      def load_existing_reference(stream, criteria)
        event = @event_store.read(stream, criteria).first
        event && event_reference(event)
      end

      def load_attempt_state(attempt_id)
        stream = @stream_factory.attempt(attempt_id)
        membership = @event_store.read(
          stream,
          EventQueries::ATTEMPT_FOR_CANDIDATE_SUBMISSION
        )
        lifecycle = @event_store.read_grouped(
          stream,
          EventQueries::ATTEMPT_LATEST_WRITE_SET_LIFECYCLE
        )
        events = SpecificStreamEventSequence.merge(membership, lifecycle.reverse)

        Domain::Attempts::State.reduce(events.map { load_event(_1) })
      end

      def load_lease_state(resource_id)
        events = @event_store.read_grouped(
          @stream_factory.resource_lease(resource_id),
          EventQueries::RESOURCE_LEASE_FOR_CANDIDATE_SUBMISSION
        ).reverse.map { load_event(_1) }

        Domain::ResourceLeases::State.reduce(events)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def future_candidate_reference(command, event_id)
        stream = @stream_factory.candidate(command.candidate_id)
        EventReference.new(
          event_id:,
          type: "CandidateSubmitted",
          stream_context: stream.context,
          stream_name: stream.stream_name,
          stream_id: stream.stream_id,
          stream_revision: 0
        )
      end

      def apply_event_plan_contract(plan, state:, command:, prepared:, candidate_event:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          state:,
          head_identity: prepared.head_identity,
          candidate_event:,
          submitted_at: prepared.submitted_at
        )
        return plan if result.success?

        raise InvalidCandidateSubmissionEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, command:, prepared:, repository_registration:, caused_by:)
        plan.writes.zip(domain_event_ids(prepared)).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: command_metadata(command),
            markers: event_markers(command, prepared.head_identity, repository_registration:),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def domain_event_ids(prepared)
        ids = [ prepared.candidate_event_id, prepared.manifest_event_id ]
        ids << prepared.build_context_event_id if prepared.build_context_event_id
        ids.concat([ prepared.head_registration_event_id, prepared.attachment_event_id ])
      end

      def event_markers(command, head_identity, repository_registration:)
        [
          "candidate:#{command.candidate_id}",
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "object-format:#{command.object_format}",
          "head-commit-oid:#{command.head_commit_oid}",
          "lease-set:#{command.lease_set_id}",
          "command:#{command.command_id}",
          head_identity.marker
        ] + @repository_marker_builder.call(repository_registration)
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

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
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
