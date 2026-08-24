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
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::ReleaseSetPreparationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @member_loader = member_loader
        @decider = decider
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
          prepared_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

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
        decision = @decider.call(state:, command:, prepared_at: preparation.prepared_at)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, prepared_at: preparation.prepared_at)
        prepared = plan.events.sole
        persisted = persist_preparation(prepared, command:, preparation:, caused_by:)
        completion = @completion_builder.release_set_prepare(
          command:,
          preparation: prepared,
          input_digest: preparation.input_digest,
          persisted_events: [ persisted ],
          completed_at: preparation.prepared_at
        )
        persist_completion(completion, command:, preparation:, caused_by:)
        Success(completion)
      end

      def verify_event_plan!(plan, state:, command:, prepared_at:)
        result = @event_plan_contract.call(plan:, state:, command:, prepared_at:)
        return if result.success?

        raise InvalidReleaseSetPreparationEventPlan, result.errors.to_h.inspect
      end

      def persist_preparation(event, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event:,
          event_id: preparation.prepared_event_id,
          metadata: command_metadata(command),
          markers: event_markers(command, event),
          caused_by:,
          correlation_id: root_correlation_id(preparation, caused_by)
        )
        @event_store.append(@stream_factory.release_set(command.release_set_id), [ physical ]).sole
      end

      def persist_completion(completion, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event: completion,
          event_id: preparation.completion_event_id,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:,
          correlation_id: root_correlation_id(preparation, caused_by)
        )
        @event_store.append(@stream_factory.command(command.command_id), [ physical ])
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion

        return Success(completion) if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest

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

      def load_completion(command_id)
        event = @event_store.read(@stream_factory.command(command_id), EventQueries::COMMAND_COMPLETION).first
        event && load_event(event)
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

      def event_markers(command, event)
        [
          "release-set:#{command.release_set_id}",
          "change-set:#{event.change_set_id}",
          "release-set-policy:#{command.policy_version}",
          "command:#{command.command_id}",
          *event.ordered_members.flat_map do |member|
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

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        )
      end
    end
  end
end
