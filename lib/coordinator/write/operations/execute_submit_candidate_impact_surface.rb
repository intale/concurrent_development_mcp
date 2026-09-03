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
        index_marker_builder: Candidates::ImpactIndexMarkerBuilder.new,
        completion_builder: CommandResultBuilder.new,
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
        @index_marker_builder = index_marker_builder
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
          registration_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        state = load_state(command.candidate_id)
        surface_event = future_surface_reference(command, state, prepared.surface_event_id)
        decision = @decider.call(
          state:,
          command:,
          surface_event:,
          derived_at: prepared.derived_at
        )
        return decision if decision.failure?

        plan = apply_event_plan_contract(
          decision.value!,
          state:,
          command:,
          surface_event:,
          derived_at: prepared.derived_at
        )
        persisted_events = persist_domain_plan(plan, state:, command:, prepared:, caused_by:)
        completion = @completion_builder.candidate_impact_surface_submit(
          command:,
          surface: plan.events.fetch(0),
          input_digest: prepared.input_digest,
          persisted_events:,
          completed_at: prepared.derived_at
        )

        Success(completion)
      end

      def load_state(candidate_id)
        submission = nil
        submission_event = nil
        manifest = nil
        manifest_event = nil
        build_context = nil
        build_context_event = nil
        existing_surface = nil
        @event_store.read_grouped(
          @stream_factory.candidate(candidate_id),
          EventQueries::CANDIDATE_FOR_IMPACT_SURFACE
        ).each do |event|
          case event.type
          when "CandidateSubmitted"
            submission = load_event(event)
            submission_event = event_reference(event)
          when "CandidateChangeManifestCaptured"
            manifest = load_event(event)
            manifest_event = event_reference(event)
          when "CandidateBuildContextCaptured"
            build_context = load_event(event)
            build_context_event = event_reference(event)
          when "CandidateImpactSurfaceDerived" then existing_surface = event_reference(event)
          end
        end

        evidence = if submission && manifest
          Candidates::ImpactSurfaceEvidenceV1.new(
            submission:,
            submission_event:,
            manifest:,
            manifest_event:,
            build_context:,
            build_context_event:
          )
        end
        Domain::Candidates::ImpactSurfaceState.new(
          evidence:,
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

      def apply_event_plan_contract(plan, state:, command:, surface_event:, derived_at:)
        result = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          surface_event:,
          derived_at:
        )
        return plan if result.success?

        raise InvalidCandidateImpactSurfaceEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, state:, command:, prepared:, caused_by:)
        surface = plan.events.fetch(0)
        event_ids = [ prepared.surface_event_id, prepared.registration_event_id ]
        plan.writes.zip(event_ids).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: command_metadata(command),
            markers: markers_for(write.event, command:, state:, surface:),
            caused_by:
          )
          @event_store.append(write.stream, [ event ]).sole
        end
      end

      def markers_for(event, command:, state:, surface:)
        markers = [
          "candidate:#{command.candidate_id}",
          "change-set:#{surface.change_set_id}",
          "work-item:#{surface.work_item_id}",
          "attempt:#{surface.attempt_id}",
          "repository:#{command.repository_id}",
          "head-commit-oid:#{command.head_commit_oid}",
          "command:#{command.command_id}"
        ]
        if event.is_a?(Events::CandidateImpactSurfaceRegisteredV1)
          markers.concat(@index_marker_builder.call(evidence: state.evidence, surface:))
        end
        markers.freeze
      end

      def future_surface_reference(command, state, event_id)
        EventReference.new(
          event_id:,
          type: "CandidateImpactSurfaceDerived",
          stream_context: "DevelopmentIntegration",
          stream_name: "Candidate",
          stream_id: command.candidate_id,
          stream_revision: state.evidence ? state.evidence.next_candidate_revision : 0
        )
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
