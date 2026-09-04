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
        stream_factory: StreamFactory.new,
        index_marker_builder: Candidates::ImpactIndexMarkerBuilder.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::CandidateImpactSurfaceEventPlan.new,
        candidate_state_loader: Candidates::StateLoader.new(event_store:)
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @index_marker_builder = index_marker_builder
        @completion_builder = completion_builder
        @event_plan_contract = event_plan_contract
        @candidate_state_loader = candidate_state_loader
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
          surface_id: @id_generator.uuid_v7,
          surface_event_id: @id_generator.uuid_v7,
          registration_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        state = load_state(command.candidate_id)
        decision = @decider.call(
          state:,
          command:,
          surface_id: prepared.surface_id
        )
        return decision if decision.failure?

        plan = apply_event_plan_contract(
          decision.value!,
          command:,
          surface_id: prepared.surface_id
        )
        persisted_events = persist_domain_plan(plan, state:, command:, prepared:, caused_by:)
        completion = @completion_builder.candidate_impact_surface_submit(
          command:,
          surface_id: prepared.surface_id,
          input_digest: prepared.input_digest,
          persisted_events:,
          completed_at: prepared.derived_at
        )

        Success(completion)
      end

      def load_state(candidate_id)
        candidate = @candidate_state_loader.call(candidate_id)
        evidence = candidate && Candidates::ImpactSurfaceEvidenceV2.new(candidate:)
        Domain::Candidates::ImpactSurfaceState.new(
          evidence:,
          existing_surface: candidate&.surface_assignment_event
        )
      end

      def apply_event_plan_contract(plan, command:, surface_id:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          surface_id:
        )
        return plan if result.success?

        raise InvalidCandidateImpactSurfaceEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, state:, command:, prepared:, caused_by:)
        event_ids = [ prepared.surface_event_id, prepared.registration_event_id ]
        surface = plan.events.fetch(0)
        plan.writes.zip(event_ids).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command),
            markers: markers_for(write.event, command:, state:, surface:),
            caused_by:
          )
          @event_store.append(write.stream, [ event ]).sole
        end
      end

      def markers_for(event, command:, state:, surface:)
        candidate = state.evidence.candidate
        markers = [
          "candidate:#{command.candidate_id}",
          "change-set:#{candidate.change_set_id}",
          "work-item:#{candidate.work_item_id}",
          "attempt:#{candidate.attempt_id}",
          "repository:#{command.repository_id}",
          "head-commit-oid:#{command.head_commit_oid}",
          "command:#{command.command_id}"
        ]
        if event.is_a?(Events::CandidateImpactSurfaceAssignedV1)
          markers.concat(@index_marker_builder.call(evidence: state.evidence, surface:))
        end
        markers.freeze
      end

      def event_metadata(event, command)
        attributes = command_metadata(command).to_h
        return EventMetadata.new(**attributes, policy_version: nil) unless event.is_a?(Events::CandidateImpactSurfaceDerivedV2)

        Metadata::CandidateImpactSurfaceV2.new(
          **attributes,
          policy_version: command.surface.policy_version,
          analyzer: command.surface.analyzer,
          manifest_digest: command.manifest_digest,
          build_context_digest: command.build_context_digest,
          surface_digest: command.surface.digest
        )
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
    end
  end
end
