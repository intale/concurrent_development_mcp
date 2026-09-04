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
        completion_builder: CommandResultBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        natural_key_registry: NaturalKeys::Registry.new(event_store:),
        work_intention_set_loader: WorkIntentionSetLoader.new(event_store:),
        work_intention_loader: WorkIntentionLoader.new(event_store:),
        work_intention_resource_loader: WorkIntentionResourceLoader.new(event_store:),
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
        @natural_key_registry = natural_key_registry
        @work_intention_set_loader = work_intention_set_loader
        @work_intention_loader = work_intention_loader
        @work_intention_resource_loader = work_intention_resource_loader
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
          candidate_fact_event_ids: Array.new(command.build_context ? 10 : 9) { @id_generator.uuid_v7 },
          head_registration_event_id: @id_generator.uuid_v7
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
        head_resolution = resolve_head_identity(prepared.head_identity)
        return head_resolution if head_resolution.failure?

        head_identity, existing_head = head_resolution.value!
        prepared = prepared.with_head_identity(head_identity)

        state_result = load_submission_state(command, existing_head:)
        return state_result if state_result.failure?

        state = state_result.value!
        decision = @decider.call(
          state:,
          command:,
          submitted_at: prepared.submitted_at,
          head_identity: prepared.head_identity
        )
        return decision if decision.failure?

        plan = apply_event_plan_contract(
          decision.value!,
          state:,
          command:,
          prepared:
        )
        persisted_events = persist_domain_plan(
          plan,
          command:,
          prepared:,
          repository_registration:,
          caused_by:
        )
        completion = @completion_builder.candidate_submit(
          command:,
          input_digest: prepared.input_digest,
          persisted_events:,
          completed_at: prepared.submitted_at
        )

        Success(completion)
      end

      def resolve_head_identity(proposed)
        result = @natural_key_registry.find(
          selector: NaturalKeys::Registry::SelectorV1.new(
            stream_context: "DevelopmentIntegration",
            stream_name: "CandidateHead",
            event_type: "CandidateHeadRegistered",
            marker: proposed.marker
          ),
          identity_from: ->(event) { candidate_head_identity_from(event, proposed) }
        )
        return registry_failure(result.failure) if result.failure?
        return Success([ proposed, nil ]) unless result.value!

        persisted = result.value!
        identity = Candidates::HeadIdentityV1.new(
          document: proposed.document,
          registry_id: persisted.identity,
          marker: proposed.marker
        )
        Success([ identity, event_reference(persisted.event) ])
      end

      def candidate_head_identity_from(event, proposed)
        registration = load_event(event)
        return unless registration.is_a?(Events::CandidateHeadRegisteredV2)
        return unless [ registration.repository_id, registration.object_format, registration.head_commit_oid ] ==
                      [ proposed.document.repository_id, proposed.document.object_format, proposed.document.head_commit_oid ]

        registration.registry_id
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError
        nil
      end

      def registry_failure(error)
        Failure(
          OutcomeError.new(
            code: :candidate_head_registry_invalid,
            message: error.message,
            details: error.to_h
          )
        )
      end

      def load_submission_state(command, existing_head:)
        attempt = load_attempt_state(command.attempt_id)
        hydration = hydrate_work_intentions(attempt, command:)
        return hydration if hydration.failure?

        attempt, current_leases = hydration.value!

        Success(Domain::Candidates::SubmissionState.new(
          existing_candidate: load_existing_reference(
            @stream_factory.candidate(command.candidate_id),
            EventQueries::CANDIDATE_EXISTENCE
          ),
          existing_head:,
          attempt:,
          current_leases:
        ))
      end

      def hydrate_work_intentions(attempt, command:)
        set_state = @work_intention_set_loader.find_by_attempt(command.attempt_id)
        return Success([ attempt, legacy_lease_observations(attempt) ]) unless set_state

        observations = set_state.members.map do |member|
          intention = @work_intention_loader.call(member.intention_id).state
          resource_result = @work_intention_resource_loader.call(
            ResourceLeaseTargetV1.new(
              resource_id: intention.resource_id,
              base_blob_oid: intention.base_blob_oid
            ),
            repository_id: intention.repository_id
          )
          return resource_result if resource_result.failure?

          resource = resource_result.value!
          reference = LeaseReferenceV2.new(
            lease_id: intention.intention_id,
            resource_id: intention.resource_id,
            resource_kind: resource.kind,
            resource_path: resource.path,
            base_blob_oid: intention.base_blob_oid,
            fencing_token: intention.fencing_token
          )
          CurrentLeaseObservationV2.new(
            reference:,
            state: legacy_lease_state(intention, resource:)
          )
        end
        released_at = observations.all? { !_1.state.released_at.nil? } ? observations.first&.state&.released_at : nil
        attempt = Domain::Attempts::State.new(
          attempt.attributes.merge(
            lease_set_id: set_state.set_id,
            lease_repository_id: set_state.repository_id,
            lease_policy_version: LeaseResourceV2::POLICY_VERSION,
            lease_resources: observations.map(&:reference),
            lease_expires_at: observations.map { _1.state.expires_at }.compact.min,
            lease_released_at: released_at
          )
        )
        Success([ attempt, observations ])
      end

      def legacy_lease_observations(attempt)
        attempt.lease_resources.map do |reference|
          CurrentLeaseObservationV2.new(
            reference:,
            state: load_lease_state(reference.resource_id)
          )
        end
      end

      def legacy_lease_state(intention, resource:)
        Domain::ResourceLeases::State.new(
          lease_id: intention.intention_id,
          lease_set_id: intention.set_id,
          resource_id: intention.resource_id,
          resource_kind: resource.kind,
          resource_path: resource.path,
          policy_version: LeaseResourceV2::POLICY_VERSION,
          mode: intention.mode,
          change_set_id: intention.change_set_id,
          work_item_id: intention.work_item_id,
          attempt_id: intention.attempt_id,
          agent_id: intention.agent_id,
          repository_id: intention.repository_id,
          object_format: intention.object_format,
          base_commit_oid: intention.base_commit_oid,
          base_blob_oid: intention.base_blob_oid,
          fencing_token: intention.fencing_token,
          acquired_at: nil,
          renewed_at: nil,
          expires_at: intention.expires_at,
          released_at: intention.withdrawn ? intention.expires_at : nil,
          expired_at: intention.expired ? intention.expires_at : nil
        )
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

      def apply_event_plan_contract(plan, state:, command:, prepared:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          head_identity: prepared.head_identity
        )
        return plan if result.success?

        raise InvalidCandidateSubmissionEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, command:, prepared:, repository_registration:, caused_by:)
        plan.writes.zip(domain_event_ids(prepared)).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command),
            markers: event_markers(
              write.event,
              command,
              prepared.head_identity,
              repository_registration:
            ),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def domain_event_ids(prepared)
        prepared.candidate_fact_event_ids + [ prepared.head_registration_event_id ]
      end

      def event_markers(event, command, head_identity, repository_registration:)
        markers = [
          "candidate:#{command.candidate_id}",
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "object-format:#{command.object_format}",
          "head-commit-oid:#{command.head_commit_oid}",
          "lease-set:#{command.lease_set_id}",
          "command:#{command.command_id}"
        ] + @repository_marker_builder.call(repository_registration)
        markers << head_identity.marker if event.is_a?(Events::CandidateHeadRegisteredV2)
        markers
      end

      def event_metadata(event, command)
        attributes = command_metadata(command).to_h
        case event
        when Events::CandidateChangeManifestCapturedV2
          Metadata::CandidateChangeManifestV2.new(
            **attributes,
            policy_version: command.manifest.policy_version,
            collector: command.manifest.collector,
            manifest_digest: command.manifest.digest
          )
        when Events::CandidateBuildContextCapturedV2
          context = command.build_context
          Metadata::CandidateBuildContextV2.new(
            **attributes,
            policy_version: context.policy_version,
            collector: context.collector,
            build_context_digest: context.digest,
            dependency_graph_digest: context.dependency_graph_digest,
            test_environment_digest: context.test_environment_digest
          )
        when Events::CandidateHeadRegisteredV2
          Metadata::MarkerCodecV1.new(
            **attributes,
            marker_codec_version: Candidates::HeadIdentityBuilder::MARKER_CODEC_VERSION
          )
        when Events::CandidateWorkIntentionSetAssignedV1
          EventMetadata.new(**attributes, policy_version: LeaseResourceV2::POLICY_VERSION)
        else
          EventMetadata.new(**attributes, policy_version: nil)
        end
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: nil
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
