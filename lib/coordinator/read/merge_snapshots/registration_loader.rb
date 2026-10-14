# frozen_string_literal: true

module Coordinator::Read::MergeSnapshots
  class RegistrationLoader
    FACT_TYPES = %w[CandidateAssignedToAttempt CandidateAssignedToRepository CandidateTargetBranchSelected
      CandidateCommitRangeDeclared CandidateChangeManifestCaptured CandidateSubmitted].freeze

    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(event)
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      members = data.fetch(:ordered_candidates).map do |id|
        events = @event_store.read(@stream_factory.candidate(id), Coordinator::Write::EventReadCriteria.new(
          event_types: FACT_TYPES, maximum_count: FACT_TYPES.length, direction: :asc))
        facts = events.to_h { [ _1.type, _1 ] }
        attempt = Coordinator::Read::CommandResults::Source.document(facts.fetch("CandidateAssignedToAttempt").data)
        range = Coordinator::Read::CommandResults::Source.document(facts.fetch("CandidateCommitRangeDeclared").data)
        { candidate_id: id,
          **attempt.slice(:change_set_id, :work_item_id, :attempt_id),
          repository_id: facts.fetch("CandidateAssignedToRepository").data.fetch("repository_id"),
          target_branch: facts.fetch("CandidateTargetBranchSelected").data.fetch("target_branch"),
          **range.slice(:object_format, :base_commit_oid, :head_commit_oid),
          manifest_digest: facts.fetch("CandidateChangeManifestCaptured").metadata.fetch("manifest_digest"),
          candidate_event: Coordinator::Read::Projections::Source.reference(facts.fetch("CandidateSubmitted")),
          manifest_event: Coordinator::Read::Projections::Source.reference(facts.fetch("CandidateChangeManifestCaptured")) }
      end
      data.merge(ordered_candidates: members)
    end
  end
end
