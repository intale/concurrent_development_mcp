# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class CandidateEvidenceV1 < Value
      Candidate = Events::CandidateSubmittedV2

      attribute :registration, Events::CandidateImpactSurfaceRegisteredV1
      attribute :registration_event, EventReference
      attribute :candidate, Candidate
      attribute :manifest, Events::CandidateChangeManifestCapturedV1
      attribute :build_context, Events::CandidateBuildContextCapturedV1.optional
      attribute :surface, Events::CandidateImpactSurfaceDerivedV1
      attribute :subject, CandidateSubjectV1
    end
  end
end
