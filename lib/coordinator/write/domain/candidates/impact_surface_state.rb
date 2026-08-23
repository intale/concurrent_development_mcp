# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Candidates
      class ImpactSurfaceState < Value
        attribute :submission, Events::CandidateSubmittedV1.optional
        attribute :manifest, Events::CandidateChangeManifestCapturedV1.optional
        attribute :build_context, Events::CandidateBuildContextCapturedV1.optional
        attribute :existing_surface, EventReference.optional
      end
    end
  end
end
