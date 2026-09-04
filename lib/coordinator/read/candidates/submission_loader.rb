# frozen_string_literal: true

module Coordinator::Read
  module Candidates
    class SubmissionLoader
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
      ].freeze

      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(candidate_id)
        events = @event_store.read(
          @stream_factory.candidate(candidate_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: FACT_TYPES,
            maximum_count: 10,
            direction: :asc
          )
        )
        facts = events.to_h { |event| [ event.type, [ load_event(event), event ] ] }
        created, created_event = fetch_fact(facts, "CandidateCreated")
        attempt, = fetch_fact(facts, "CandidateAssignedToAttempt")
        repository, = fetch_fact(facts, "CandidateAssignedToRepository")
        branch, = fetch_fact(facts, "CandidateTargetBranchSelected")
        commit_range, = fetch_fact(facts, "CandidateCommitRangeDeclared")
        checkpoint, = fetch_fact(facts, "CandidateCheckpointKindSelected")
        intention_set, = fetch_fact(facts, "CandidateWorkIntentionSetAssigned")
        manifest, manifest_event = fetch_fact(facts, "CandidateChangeManifestCaptured")
        submitted, submitted_event = fetch_fact(facts, "CandidateSubmitted")
        build_context, build_context_event = facts["CandidateBuildContextCaptured"]

        identities = [
          created, attempt, repository, branch, commit_range, checkpoint,
          intention_set, manifest, build_context, submitted
        ].compact.map(&:candidate_id)
        unless identities.all? { _1 == candidate_id }
          raise InvalidProjectionSource, "Candidate facts disagree on candidate_id"
        end

        CandidateSubmissionViewV2.new(
          candidate_id:,
          change_set_id: attempt.change_set_id,
          work_item_id: attempt.work_item_id,
          attempt_id: attempt.attempt_id,
          agent_id: created_event.metadata.fetch("actor_id"),
          repository_id: repository.repository_id,
          target_branch: branch.target_branch,
          object_format: commit_range.object_format,
          base_commit_oid: commit_range.base_commit_oid,
          head_commit_oid: commit_range.head_commit_oid,
          checkpoint_kind: checkpoint.checkpoint_kind,
          intention_set_id: intention_set.intention_set_id,
          lease_references: load_lease_references(intention_set.intention_set_id),
          manifest_digest: manifest_event.metadata.fetch("manifest_digest"),
          build_context_digest: build_context_event&.metadata&.fetch("build_context_digest"),
          evidence_status: "attributed_unverified",
          manifest:,
          build_context:,
          submitted_event:,
          manifest_event:,
          build_context_event:
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def fetch_fact(facts, type)
        facts.fetch(type) { raise InvalidProjectionSource, "Candidate is missing #{type}" }
      end

      def load_lease_references(set_id)
        memberships = @event_store.read(
          @stream_factory.work_intention_set(set_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "WorkIntentionAddedToSet" ],
            maximum_count: Coordinator::Shared::Types::WRITE_SET_RESOURCE_MAXIMUM_COUNT,
            direction: :asc
          )
        ).map { load_event(_1) }
        if memberships.empty? || memberships.any? { _1.set_id != set_id }
          raise InvalidProjectionSource, "Candidate work-intention set is incomplete"
        end

        memberships.map do |membership|
          declaration = load_first(
            @stream_factory.resource_work_intention(membership.intention_id),
            "ResourceWorkIntentionDeclared"
          )
          registration = load_first(
            @stream_factory.resource(membership.resource_id),
            "ResourceRegistered"
          )
          unless declaration.intention_id == membership.intention_id &&
                 declaration.resource_id == membership.resource_id &&
                 declaration.set_id == set_id &&
                 registration.resource_id == membership.resource_id
            raise InvalidProjectionSource, "Candidate work-intention membership is inconsistent"
          end

          Coordinator::Write::LeaseReferenceV2.new(
            lease_id: declaration.intention_id,
            resource_id: declaration.resource_id,
            resource_kind: registration.kind,
            resource_path: registration.normalized_path,
            base_blob_oid: declaration.base_blob_oid,
            fencing_token: declaration.fencing_token
          )
        end
      end

      def load_first(stream, event_type)
        event = @event_store.read(
          stream,
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ event_type ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Candidate evidence is missing #{event_type}" unless event

        load_event(event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
