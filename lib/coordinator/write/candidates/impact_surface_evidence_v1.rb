# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactSurfaceEvidenceV1 < Value
      attribute :submission, Events::CandidateSubmittedV1
      attribute :submission_event, EventReference
      attribute :manifest, Events::CandidateChangeManifestCapturedV1
      attribute :manifest_event, EventReference
      attribute :build_context, Events::CandidateBuildContextCapturedV1.optional
      attribute :build_context_event, EventReference.optional

      def next_candidate_revision
        [ manifest_event, build_context_event ].compact.map(&:stream_revision).max + 1
      end
    end
  end
end
