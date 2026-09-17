# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateSubjectMigrationV1 < Value
      attribute :source_subject, CandidateObligations::CandidateSubjectV1
      attribute :target_subject, CandidateObligations::CandidateSubjectV1
      attribute :context, CandidateContextV1
      attribute :manifest, Events::CandidateChangeManifestCapturedV1
      attribute :build_context, Events::CandidateBuildContextCapturedV1.optional
      attribute :surface, Events::CandidateImpactSurfaceDerivedV1
      attribute :registration, Events::CandidateImpactSurfaceRegisteredV1

      def source_evidence
        CandidateObligations::CandidateEvidenceV1.new(
          registration:,
          registration_event: source_subject.registration_event,
          candidate: context.source_candidate,
          manifest:,
          build_context:,
          surface:,
          subject: source_subject
        )
      end
    end
  end
end
