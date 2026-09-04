# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class CandidateHistoryV1 < Value
      Candidate = Candidates::StateV2

      attribute :requested, RequestedCandidateV1
      attribute :candidate, Candidate.optional
      attribute :manifest, Events::CandidateChangeManifestCapturedV2.optional
      attribute :candidate_event, EventReference.optional
      attribute :manifest_event, EventReference.optional
    end
  end
end
