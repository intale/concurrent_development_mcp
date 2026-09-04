# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class CandidatesV1
      PROJECTION = ProjectionDefinition.new(name: "candidates", version: 1)

      def initialize(
        submission_loader:,
        impact_surface_loader:,
        contract: Contracts::CandidateSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        candidates: Repositories::Candidates.new,
        candidate_impacts: Repositories::CandidateImpacts.new(candidates:),
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @submission_loader = submission_loader
        @impact_surface_loader = impact_surface_loader
        @candidates = candidates
        @candidate_impacts = candidate_impacts
        @processed_events = processed_events
      end

      def call(event)
        payload = load_payload(event)
        verify_stream_identity!(event, payload)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: Time.now.utc
          )

          project(event, payload)
        end

        nil
      end

      private

      def load_payload(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, payload)
        return if event.stream.stream_id == payload.candidate_id

        raise InvalidProjectionSource, "Candidate identity does not match its source stream"
      end

      def project(event, payload)
        case payload
        when Coordinator::Write::Events::CandidateCreatedV1,
             Coordinator::Write::Events::CandidateAssignedToAttemptV1,
             Coordinator::Write::Events::CandidateAssignedToRepositoryV1,
             Coordinator::Write::Events::CandidateTargetBranchSelectedV1,
             Coordinator::Write::Events::CandidateCommitRangeDeclaredV1,
             Coordinator::Write::Events::CandidateCheckpointKindSelectedV1,
             Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1,
             Coordinator::Write::Events::CandidateChangeManifestCapturedV2,
             Coordinator::Write::Events::CandidateBuildContextCapturedV2
          true
        when Coordinator::Write::Events::CandidateSubmittedV3
          submission = @submission_loader.call(payload.candidate_id)
          @candidates.store_submission(candidate: submission)
          @candidate_impacts.store_manifest(manifest: submission.manifest)
          @candidate_impacts.store_build_context(build_context: submission.build_context) if submission.build_context
        when Coordinator::Write::Events::CandidateImpactSurfaceAssignedV1
          source = @impact_surface_loader.call(payload.surface_id)
          @candidate_impacts.store_surface(event: source.event, surface: source.surface)
        else
          raise UnknownProjectionEvent, payload.class.name
        end
      end
    end
  end
end
