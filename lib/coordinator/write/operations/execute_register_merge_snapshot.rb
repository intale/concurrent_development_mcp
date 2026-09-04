# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRegisterMergeSnapshot < Dry::Operation
      TOOL_NAME = "merge_snapshot_register"

      def initialize(
        event_store:,
        preparer: PrepareRegisterMergeSnapshot.new,
        decider: Domain::MergeSnapshots::Register.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        commit_identity_builder: MergeSnapshots::CommitIdentityBuilder.new,
        snapshot_digest_builder: MergeSnapshots::SnapshotDigestBuilder.new,
        candidate_loader: MergeSnapshots::CandidateLoader.new(event_store:),
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        natural_key_registry: NaturalKeys::Registry.new(event_store:),
        event_plan_contract: Contracts::MergeSnapshotRegistrationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @commit_identity_builder = commit_identity_builder
        @snapshot_digest_builder = snapshot_digest_builder
        @candidate_loader = candidate_loader
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @natural_key_registry = natural_key_registry
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        MergeSnapshotRegistrationPreparationV1.new(
          registered_at: @clock.now,
          input_digest: @input_digest.merge_snapshot_register(command),
          commit_identity: @commit_identity_builder.call(
            repository_id: command.repository_id,
            object_format: command.object_format,
            merge_commit_oid: command.merge_commit_oid
          ),
          snapshot_event_id: @id_generator.uuid_v7,
          commit_registration_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        commit_resolution = resolve_commit_identity(preparation.commit_identity)
        return commit_resolution if commit_resolution.failure?

        commit_identity, existing_commit = commit_resolution.value!
        preparation = preparation.with_commit_identity(commit_identity)

        state = load_state(command, existing_commit:)
        decision = @decider.call(
          state:,
          command:,
          commit_identity: preparation.commit_identity
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_plan!(plan, state:, command:, preparation:)
        snapshot_digest = @snapshot_digest_builder.call(command:, candidates: state.candidates)
        persisted = persist_plan(plan, command:, preparation:, caused_by:, snapshot_digest:)
        completion = @completion_builder.merge_snapshot_register(
          command:,
          snapshot_digest:,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.registered_at,
          registered_at: preparation.registered_at
        )
        Success(completion)
      end

      def resolve_commit_identity(proposed)
        result = @natural_key_registry.find(
          selector: NaturalKeys::Registry::SelectorV1.new(
            stream_context: "DevelopmentIntegration",
            stream_name: "MergeSnapshotCommit",
            event_type: "MergeSnapshotCommitRegistered",
            marker: proposed.marker
          ),
          identity_from: ->(event) { merge_commit_identity_from(event, proposed) }
        )
        return registry_failure(result.failure) if result.failure?
        return Success([ proposed, nil ]) unless result.value!

        persisted = result.value!
        identity = MergeSnapshots::CommitIdentityV1.new(
          document: proposed.document,
          registry_id: persisted.identity,
          marker: proposed.marker
        )
        Success([ identity, event_reference(persisted.event) ])
      end

      def merge_commit_identity_from(event, proposed)
        registration = load_event(event)
        return unless registration.is_a?(Events::MergeSnapshotCommitRegisteredV2)
        return unless [ registration.repository_id, registration.object_format, registration.merge_commit_oid ] ==
                      [ proposed.document.repository_id, proposed.document.object_format, proposed.document.merge_commit_oid ]

        registration.registry_id
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError
        nil
      end

      def registry_failure(error)
        Failure(
          OutcomeError.new(
            code: :merge_snapshot_commit_registry_invalid,
            message: error.message,
            details: error.to_h
          )
        )
      end

      def load_state(command, existing_commit:)
        Domain::MergeSnapshots::RegistrationState.new(
          existing_snapshot: existing_reference(
            @stream_factory.merge_snapshot(command.merge_snapshot_id),
            EventQueries::MERGE_SNAPSHOT_REGISTRATION
          ),
          existing_commit:,
          candidates: command.ordered_candidates.map { @candidate_loader.call(_1) }
        )
      end

      def existing_reference(stream, criteria)
        event = @event_store.read(stream, criteria).first
        event && event_reference(event)
      end

      def verify_plan!(plan, state:, command:, preparation:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          state:,
          commit_identity: preparation.commit_identity
        )
        return if result.success?

        raise InvalidMergeSnapshotRegistrationEventPlan, result.errors.to_h.inspect
      end

      def persist_plan(plan, command:, preparation:, caused_by:, snapshot_digest:)
        ids = [ preparation.snapshot_event_id, preparation.commit_registration_event_id ]
        parent = caused_by
        correlation_id = caused_by&.correlation_id || preparation.correlation_id
        plan.writes.zip(ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command, snapshot_digest),
            markers: event_markers(command, preparation.commit_identity, plan.events.fetch(0)),
            caused_by: parent,
            correlation_id:
          )
          persisted = @event_store.append(write.stream, [ physical ]).sole
          parent = persisted
          persisted
        end
      end

      def event_markers(command, identity, snapshot)
        markers = [
          "merge-snapshot:#{command.merge_snapshot_id}",
          "repository:#{command.repository_id}",
          "target-branch:#{command.target_branch}",
          "target-base-commit-oid:#{command.target_base_commit_oid}",
          "merge-commit-oid:#{command.merge_commit_oid}",
          "command:#{command.command_id}",
          identity.marker
        ]
        snapshot.ordered_candidates.each do |candidate_id|
          markers.concat([
            "candidate:#{candidate_id}"
          ])
        end
        markers
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
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

      def event_metadata(event, command, snapshot_digest)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        }
        case event
        when Events::MergeSnapshotRegisteredV2
          Metadata::MergeSnapshotV2.new(**attributes, snapshot_digest:)
        when Events::MergeSnapshotCommitRegisteredV2
          Metadata::MarkerCodecV1.new(**attributes, marker_codec_version: "compound-marker-v2")
        else
          raise "Unexpected merge-snapshot registration event #{event.class.name}"
        end
      end
    end
  end
end
