# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class CandidateEvidenceLoader
      def initialize(
        event_store:,
        exact_loader: ExactEventLoader.new(event_store:),
        evidence_contract: Contracts::CandidateObligationEvidence.new
      )
        @exact_loader = exact_loader
        @evidence_contract = evidence_contract
      end

      def call(registration_reference)
        registration = payload!(@exact_loader.call(registration_reference), Events::CandidateImpactSurfaceRegisteredV1)
        candidate = payload!(
          @exact_loader.call(registration.candidate_event),
          Events::CandidateSubmittedV2
        )
        manifest = payload!(@exact_loader.call(registration.manifest_event), Events::CandidateChangeManifestCapturedV1)
        build_context = registration.build_context_event && payload!(
          @exact_loader.call(registration.build_context_event),
          Events::CandidateBuildContextCapturedV1
        )
        surface = payload!(@exact_loader.call(registration.surface_event), Events::CandidateImpactSurfaceDerivedV1)
        evidence = CandidateEvidenceV1.new(
          registration:,
          registration_event: registration_reference,
          candidate:,
          manifest:,
          build_context:,
          surface:,
          subject: build_subject(registration_reference, registration, candidate)
        )
        validation = @evidence_contract.call(evidence:)
        return evidence if validation.success?

        raise InvalidHistory.new(
          reason: "candidate_evidence_mismatch",
          evidence: validation.errors.to_h
        )
      end

      private

      def payload!(persisted, *expected_classes)
        return persisted.payload if expected_classes.any? { persisted.payload.is_a?(_1) }

        raise InvalidHistory.new(
          reason: "referenced_event_type_invalid",
          evidence: {
            reference: persisted.reference.to_h,
            expected_classes: expected_classes.map(&:name),
            actual_class: persisted.payload.class.name
          }
        )
      end

      def build_subject(registration_reference, registration, candidate)
        CandidateSubjectV1.new(
          candidate_id: candidate.candidate_id,
          change_set_id: candidate.change_set_id,
          work_item_id: candidate.work_item_id,
          attempt_id: candidate.attempt_id,
          repository_id: candidate.repository_id,
          target_branch: candidate.target_branch,
          object_format: candidate.object_format,
          base_commit_oid: candidate.base_commit_oid,
          head_commit_oid: candidate.head_commit_oid,
          manifest_digest: candidate.manifest_digest,
          build_context_digest: candidate.build_context_digest,
          surface_digest: registration.surface_digest,
          candidate_event: registration.candidate_event,
          manifest_event: registration.manifest_event,
          build_context_event: registration.build_context_event,
          surface_event: registration.surface_event,
          registration_event: registration_reference
        )
      end
    end
  end
end
