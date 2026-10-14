# frozen_string_literal: true

module Coordinator::Read::Candidates
  class SubmissionLoader
    FACT_TYPES = %w[CandidateCreated CandidateAssignedToAttempt CandidateAssignedToRepository CandidateTargetBranchSelected
      CandidateCommitRangeDeclared CandidateCheckpointKindSelected CandidateWorkIntentionSetAssigned
      CandidateChangeManifestCaptured CandidateBuildContextCaptured CandidateSubmitted].freeze

    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new,
      fact_reader: Coordinator::Read::CommandResults::FactReader.new(event_store:))
      @event_store, @stream_factory, @fact_reader = event_store, stream_factory, fact_reader
    end

    def call(candidate_id)
      events = @event_store.read(@stream_factory.candidate(candidate_id), Coordinator::Write::EventReadCriteria.new(
        event_types: FACT_TYPES, maximum_count: 10, direction: :asc))
      facts = events.to_h { [ _1.type, _1 ] }
      created = facts.fetch("CandidateCreated")
      attempt = facts.fetch("CandidateAssignedToAttempt").data
      range = facts.fetch("CandidateCommitRangeDeclared").data
      manifest = facts.fetch("CandidateChangeManifestCaptured")
      context = facts["CandidateBuildContextCaptured"]
      input = @fact_reader.instruction(created.metadata.fetch("command_id")).fetch("input")

      Coordinator::Read::CandidateSubmissionViewV2.new(
        candidate_id:, change_set_id: attempt.fetch("change_set_id"), work_item_id: attempt.fetch("work_item_id"),
        attempt_id: attempt.fetch("attempt_id"), agent_id: created.metadata.fetch("actor_id"),
        repository_id: facts.fetch("CandidateAssignedToRepository").data.fetch("repository_id"),
        target_branch: facts.fetch("CandidateTargetBranchSelected").data.fetch("target_branch"),
        object_format: range.fetch("object_format"), base_commit_oid: range.fetch("base_commit_oid"), head_commit_oid: range.fetch("head_commit_oid"),
        checkpoint_kind: facts.fetch("CandidateCheckpointKindSelected").data.fetch("checkpoint_kind"),
        intention_set_id: facts.fetch("CandidateWorkIntentionSetAssigned").data.fetch("intention_set_id"),
        intentions: intention_references(input.fetch("intentions")), manifest_digest: manifest.metadata.fetch("manifest_digest"),
        build_context_digest: context&.metadata&.fetch("build_context_digest"), evidence_status: "attributed_unverified",
        manifest: Coordinator::Read::CommandResults::Source.document(manifest.data),
        build_context: context && Coordinator::Read::CommandResults::Source.document(context.data),
        created_event: created, submitted_event: facts.fetch("CandidateSubmitted"), manifest_event: manifest, build_context_event: context)
    end

    private

    def intention_references(references)
      references.map do |reference|
        declaration = @fact_reader.first(:resource_work_intention, reference.fetch("intention_id"), "ResourceWorkIntentionDeclared").data
        resource = @fact_reader.first(:resource, reference.fetch("resource_id"), "ResourceRegistered").data
        Coordinator::Read::CommandResults::Source.document(reference).merge(
          resource_kind: resource.fetch("kind"), resource_path: resource.fetch("normalized_path"),
          **Coordinator::Read::CommandResults::Source.document(declaration.slice("base_blob_oid", "mode", "purpose", "context")))
      end.sort_by { _1.fetch(:resource_id).b }
    end
  end
end
