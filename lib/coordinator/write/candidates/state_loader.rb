# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class StateLoader
      FACT_TYPES = %w[
        CandidateCreated
        CandidateAssignedToAttempt
        CandidateAssignedToRepository
        CandidateTargetBranchSelected
        CandidateCommitRangeDeclared
        CandidateCheckpointKindSelected
        CandidateWorkIntentionSetAssigned
        CandidateChangeManifestCaptured
        CandidateBuildContextCaptured
        CandidateSubmitted
        CandidateImpactSurfaceAssigned
      ].freeze

      def initialize(event_store:, schema_registry: EventSchemaRegistry.new, stream_factory: StreamFactory.new)
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(candidate_id)
        events = @event_store.read(
          @stream_factory.candidate(candidate_id),
          EventReadCriteria.new(event_types: FACT_TYPES, maximum_count: 11, direction: :asc)
        )
        return if events.empty?

        build_state(candidate_id, events)
      end

      private

      def build_state(candidate_id, events)
        facts = events.to_h { |event| [ event.type, [ load_event(event), event ] ] }
        created, created_event = fetch_fact(facts, "CandidateCreated")
        attempt, = fetch_fact(facts, "CandidateAssignedToAttempt")
        repository, = fetch_fact(facts, "CandidateAssignedToRepository")
        branch, = fetch_fact(facts, "CandidateTargetBranchSelected")
        range, = fetch_fact(facts, "CandidateCommitRangeDeclared")
        checkpoint, = fetch_fact(facts, "CandidateCheckpointKindSelected")
        intention, = fetch_fact(facts, "CandidateWorkIntentionSetAssigned")
        manifest, manifest_event = fetch_fact(facts, "CandidateChangeManifestCaptured")
        submitted, submitted_event = fetch_fact(facts, "CandidateSubmitted")
        build_context, build_context_event = facts["CandidateBuildContextCaptured"]
        assignment, assignment_event = facts["CandidateImpactSurfaceAssigned"]

        identifiers = [
          created.candidate_id, attempt.candidate_id, repository.candidate_id,
          branch.candidate_id, range.candidate_id, checkpoint.candidate_id,
          intention.candidate_id, manifest.candidate_id, submitted.candidate_id
        ]
        unless identifiers.all? { _1 == candidate_id }
          raise InvalidHistory, "Candidate facts disagree on candidate_id"
        end

        StateV2.new(
          candidate_id:,
          change_set_id: attempt.change_set_id,
          work_item_id: attempt.work_item_id,
          attempt_id: attempt.attempt_id,
          agent_id: created_event.metadata.fetch("actor_id"),
          repository_id: repository.repository_id,
          target_branch: branch.target_branch,
          object_format: range.object_format,
          base_commit_oid: range.base_commit_oid,
          head_commit_oid: range.head_commit_oid,
          checkpoint_kind: checkpoint.checkpoint_kind,
          intention_set_id: intention.intention_set_id,
          manifest_digest: manifest_event.metadata.fetch("manifest_digest"),
          build_context_digest: build_context_event&.metadata&.fetch("build_context_digest"),
          manifest:,
          build_context:,
          submission_event: event_reference(submitted_event),
          manifest_event: event_reference(manifest_event),
          build_context_event: build_context_event && event_reference(build_context_event),
          surface_id: assignment&.surface_id,
          surface_assignment_event: assignment_event && event_reference(assignment_event),
          latest_revision: events.last.stream_revision
        )
      end

      def fetch_fact(facts, type)
        facts.fetch(type) { raise InvalidHistory, "Candidate is missing #{type}" }
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
    end
  end
end
