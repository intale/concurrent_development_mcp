# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecutePrepareReleaseSet < Dry::Operation
      TOOL_NAME = "release_set_prepare"

      def initialize(
        event_store:,
        preparer: PrepareReleaseSet.new,
        member_loader: ReleaseSets::MemberLoader.new(event_store:),
        decider: Domain::ReleaseSets::Prepare.new,
        release_digest_builder: ReleaseSets::ReleaseDigestBuilder.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::ReleaseSetPreparationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @member_loader = member_loader
        @decider = decider
        @release_digest_builder = release_digest_builder
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
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
        ReleaseSetPreparationV1.new(
          prepared_at: @clock.now,
          input_digest: @input_digest.release_set_prepare(command),
          event_ids: (command.ordered_members.length + 3).times.map { @id_generator.uuid_v7 },
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        existing = @event_store.read(
          @stream_factory.release_set(command.release_set_id),
          EventQueries::RELEASE_SET_PREPARATION
        ).first
        members = command.ordered_members.each_with_index.map do |requested, index|
          result = @member_loader.call(
            requested,
            position: index + 1,
            actor: command.actor,
            command_id: command.command_id,
            evaluated_at: preparation.prepared_at
          )
          return result if result.failure?

          result.value!
        end
        state = Domain::ReleaseSets::PreparationStateV1.new(
          existing_preparation: existing && event_reference(existing),
          ordered_members: members
        )
        decision = @decider.call(state:, command:)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:)
        change_set_id = state.ordered_members.map(&:change_set_id).uniq.sole
        release_digest = @release_digest_builder.call(
          release_set_id: command.release_set_id,
          change_set_id:,
          ordered_members: state.ordered_members,
          policy_version: command.policy_version
        )
        persisted = persist_plan(
          plan,
          state:,
          command:,
          preparation:,
          release_digest:,
          caused_by:
        )
        prepared_index = state.ordered_members.length + 1
        completion = @completion_builder.release_set_prepare(
          command:,
          change_set_id:,
          ordered_members: state.ordered_members.map do |member|
            ReleaseSets::MemberSummaryV2.new(
              position: member.position,
              repository_id: member.repository_id,
              candidate_id: member.ordered_candidates.sole.candidate_id
            )
          end,
          release_digest:,
          prepared_event: persisted.fetch(prepared_index),
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.prepared_at
        )
        Success(completion)
      end

      def verify_event_plan!(plan, state:, command:)
        result = @event_plan_contract.call(plan:, state:, command:)
        return if result.success?

        raise InvalidReleaseSetPreparationEventPlan, result.errors.to_h.inspect
      end

      def persist_plan(plan, state:, command:, preparation:, release_digest:, caused_by:)
        parent = caused_by
        correlation_id = caused_by&.correlation_id || preparation.correlation_id
        plan.writes.zip(preparation.event_ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command, release_digest),
            markers: event_markers(command, state),
            caused_by: parent,
            correlation_id:
          )
          persisted = @event_store.append(write.stream, [ physical ]).sole
          parent = persisted
          persisted
        end
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

      def event_markers(command, state)
        change_set_id = state.ordered_members.map(&:change_set_id).uniq.sole
        [
          "release-set:#{command.release_set_id}",
          "change-set:#{change_set_id}",
          "release-set-policy:#{command.policy_version}",
          "command:#{command.command_id}",
          *state.ordered_members.flat_map do |member|
            [
              "repository:#{member.repository_id}",
              "merge-snapshot:#{member.merge_snapshot_id}",
              "merge-authorization:#{member.authorization_event.stream_id}"
            ]
          end
        ]
      end

      def root_correlation_id(preparation, caused_by)
        preparation.correlation_id unless caused_by
      end

      def event_metadata(event, command, release_digest)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        }
        if event.is_a?(Events::ReleaseSetPreparedV2)
          Metadata::ReleaseSetPreparedV2.new(**attributes, release_digest:)
        else
          EventMetadata.new(**attributes)
        end
      end
    end
  end
end
