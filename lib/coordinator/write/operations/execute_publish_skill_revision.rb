# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecutePublishSkillRevision < Dry::Operation
      TOOL_NAME = "skill_publish"

      def initialize(
        event_store:,
        preparer: PreparePublishSkillRevision.new,
        decider: Domain::Skills::Publish.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        publication_loader: Skills::PersistedPublicationLoader.new(schema_registry:),
        stream_factory: StreamFactory.new,
        marker_builder: Skills::MarkerBuilder.new,
        completion_builder: CommandCompletionBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @publication_loader = publication_loader
        @stream_factory = stream_factory
        @marker_builder = marker_builder
        @completion_builder = completion_builder
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
        SkillPublicationPreparationV1.new(
          published_at: @clock.now,
          input_digest: @input_digest.skill_publish(command),
          domain_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        state_result = load_skill_state(command.skill_id)
        return state_result if state_result.failure?

        state = state_result.value!
        decision = @decider.call(state:, command:, published_at: preparation.published_at)
        return decision if decision.failure?

        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: TOOL_NAME,
          command_id: command.command_id
        )
        persisted_events = persist_domain_plan(
          decision.value!,
          command:,
          event_id: preparation.domain_event_id,
          caused_by:
        )
        publication = decision.value!.events.sole
        completion = @completion_builder.skill_publish(
          command:,
          publication:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.published_at
        )
        persist_completion(
          completion,
          command:,
          event_id: preparation.completion_event_id,
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

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def load_skill_state(skill_id)
        events = @event_store.read_grouped(
          @stream_factory.skill(skill_id),
          EventQueries::SKILL_LATEST_REVISION
        )
        return Success(Domain::Skills::State.initial) if events.empty?

        @publication_loader.call(events.sole).fmap do |publication|
          Domain::Skills::State.reduce([ publication ])
        end
      end

      def persist_domain_plan(plan, command:, event_id:, caused_by:)
        expected_stream = @stream_factory.skill(command.skill_id)
        unless plan.writes.length == 1 && plan.writes.first.stream == expected_stream
          raise "PublishSkillRevision domain plan must contain one write to its Skill stream"
        end

        identity = Skills::IdentityV1.new(
          skill_id: command.skill_id,
          name: command.name,
          scope: command.scope
        )
        persisted = @event_factory.build!(
          event: plan.writes.first.event,
          event_id:,
          metadata: command_metadata(command),
          markers: @marker_builder.call(identity:, command_id: command.command_id),
          caused_by:
        )
        @event_store.append(expected_stream, [ persisted ])
      end

      def persist_completion(completion, command:, event_id:, caused_by:)
        persisted = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )
        @event_store.append(@stream_factory.command(command.command_id), [ persisted ])
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "skill-repository/v1"
        )
      end
    end
  end
end
