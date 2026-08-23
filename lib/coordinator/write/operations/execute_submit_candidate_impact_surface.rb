# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteSubmitCandidateImpactSurface < Dry::Operation
      TOOL_NAME = "candidate_impact_surface_submit"

      def initialize(
        event_store:,
        preparer: PrepareSubmitCandidateImpactSurface.new,
        decider: Domain::Candidates::SubmitImpactSurface.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::CandidateImpactSurfaceEventPlan.new
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
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          prepared = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        PreparedCandidateImpactSurfaceSubmission.new(
          derived_at: @clock.now,
          input_digest: @input_digest.candidate_impact_surface_submit(command),
          surface_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        replay = replay_result(command:, input_digest: prepared.input_digest)
        return replay if replay

        state = load_state(command.candidate_id)
        decision = @decider.call(state:, command:, derived_at: prepared.derived_at)
        return decision if decision.failure?

        plan = apply_event_plan_contract(
          decision.value!,
          state:,
          command:,
          derived_at: prepared.derived_at
        )
        persisted_events = persist_surface(
          plan.events.sole,
          command:,
          event_id: prepared.surface_event_id,
          caused_by:
        )
        completion = @completion_builder.candidate_impact_surface_submit(
          command:,
          surface: plan.events.sole,
          input_digest: prepared.input_digest,
          persisted_events:,
          completed_at: prepared.derived_at
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

      def load_state(candidate_id)
        submission = nil
        manifest = nil
        build_context = nil
        existing_surface = nil
        @event_store.read_grouped(
          @stream_factory.candidate(candidate_id),
          EventQueries::CANDIDATE_FOR_IMPACT_SURFACE
        ).each do |event|
          case event.type
          when "CandidateSubmitted" then submission = load_event(event)
          when "CandidateChangeManifestCaptured" then manifest = load_event(event)
          when "CandidateBuildContextCaptured" then build_context = load_event(event)
          when "CandidateImpactSurfaceDerived" then existing_surface = event_reference(event)
          end
        end

        Domain::Candidates::ImpactSurfaceState.new(
          submission:,
          manifest:,
          build_context:,
          existing_surface:
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def apply_event_plan_contract(plan, state:, command:, derived_at:)
        result = @event_plan_contract.call(plan:, state:, command:, derived_at:)
        return plan if result.success?

        raise InvalidCandidateImpactSurfaceEventPlan, result.errors.to_h.inspect
      end

      def persist_surface(surface, command:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: surface,
          event_id:,
          metadata: command_metadata(command),
          markers: event_markers(command, surface),
          caused_by:
        )
        @event_store.append(@stream_factory.candidate(command.candidate_id), [ event ])
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

      def event_markers(command, surface)
        [
          "candidate:#{command.candidate_id}",
          "change-set:#{surface.change_set_id}",
          "work-item:#{surface.work_item_id}",
          "attempt:#{surface.attempt_id}",
          "repository:#{command.repository_id}",
          "head-commit-oid:#{command.head_commit_oid}",
          "command:#{command.command_id}"
        ]
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: Candidates::ImpactSurfaceDocumentV1::SCHEMA
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
    end
  end
end
