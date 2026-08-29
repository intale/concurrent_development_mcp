# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class CandidatesV1
      PROJECTION = ProjectionDefinition.new(name: "candidates", version: 1)

      def initialize(
        contract: Contracts::CandidateSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        candidates: Repositories::Candidates.new,
        candidate_impacts: Repositories::CandidateImpacts.new(candidates:),
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
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
        when Coordinator::Write::Events::CandidateSubmittedV2
          @candidates.store_submission(event:, candidate: payload)
        when Coordinator::Write::Events::CandidateChangeManifestCapturedV1
          @candidates.store_manifest(event:, manifest: payload)
          @candidate_impacts.store_manifest(manifest: payload)
        when Coordinator::Write::Events::CandidateBuildContextCapturedV1
          @candidates.store_build_context(event:, build_context: payload)
          @candidate_impacts.store_build_context(build_context: payload)
        when Coordinator::Write::Events::CandidateImpactSurfaceDerivedV1
          @candidate_impacts.store_surface(event:, surface: payload)
        end
      end
    end
  end
end
