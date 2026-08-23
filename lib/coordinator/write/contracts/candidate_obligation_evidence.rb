# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateObligationEvidence < Dry::Validation::Contract
      params do
        required(:evidence).value(Types.Instance(CandidateObligations::CandidateEvidenceV1))
      end

      rule(:evidence) do
        evidence = value
        registration = evidence.registration
        candidate = evidence.candidate
        manifest = evidence.manifest
        context = evidence.build_context
        surface = evidence.surface
        report = ->(field, message) { key([ :evidence, field ]).failure(message) }

        validate_registration_reference(evidence, report)
        validate_candidate(registration, candidate, report)
        validate_manifest(registration, candidate, manifest, report)
        validate_build_context(registration, candidate, context, report)
        validate_surface(registration, candidate, surface, report)
        validate_subject(evidence, report)
      end

      private

      def validate_registration_reference(evidence, report)
        reference = evidence.registration_event
        registration = evidence.registration
        valid = reference.type == "CandidateImpactSurfaceRegistered" &&
                reference.stream_context == "DevelopmentIntegration" &&
                reference.stream_name == "CandidateImpactRegistry" &&
                reference.stream_id == registration.change_set_id
        report.call(:registration_event, "must identify the exact ChangeSet registry") unless valid
      end

      def validate_candidate(registration, candidate, report)
        fields = %i[
          candidate_id change_set_id work_item_id attempt_id repository_id target_branch
          object_format base_commit_oid head_commit_oid
        ]
        matches = fields.all? { registration.public_send(_1) == candidate.public_send(_1) }
        report.call(:candidate, "must match the registered Candidate identity") unless matches
        unless candidate_reference?(registration.candidate_event, "CandidateSubmitted", candidate.candidate_id)
          report.call(:candidate, "must be loaded from the registered Candidate reference")
        end
      end

      def validate_manifest(registration, candidate, manifest, report)
        matches = manifest.candidate_id == candidate.candidate_id &&
                  manifest.repository_id == candidate.repository_id &&
                  manifest.target_branch == candidate.target_branch &&
                  manifest.object_format == candidate.object_format &&
                  manifest.base_commit_oid == candidate.base_commit_oid &&
                  manifest.head_commit_oid == candidate.head_commit_oid &&
                  manifest.manifest_digest == candidate.manifest_digest &&
                  candidate_reference?(
                    registration.manifest_event,
                    "CandidateChangeManifestCaptured",
                    candidate.candidate_id
                  )
        report.call(:manifest, "must match the registered Candidate manifest") unless matches
      end

      def validate_build_context(registration, candidate, context, report)
        if candidate.build_context_digest
          matches = context && registration.build_context_event &&
                    context.candidate_id == candidate.candidate_id &&
                    context.repository_id == candidate.repository_id &&
                    context.object_format == candidate.object_format &&
                    context.head_commit_oid == candidate.head_commit_oid &&
                    context.build_context_digest == candidate.build_context_digest &&
                    candidate_reference?(
                      registration.build_context_event,
                      "CandidateBuildContextCaptured",
                      candidate.candidate_id
                    )
          report.call(:build_context, "must match the registered Candidate build context") unless matches
        elsif context || registration.build_context_event
          report.call(:build_context, "must be absent when the Candidate has no build context")
        end
      end

      def validate_surface(registration, candidate, surface, report)
        matches = surface.candidate_id == candidate.candidate_id &&
                  surface.change_set_id == candidate.change_set_id &&
                  surface.work_item_id == candidate.work_item_id &&
                  surface.attempt_id == candidate.attempt_id &&
                  surface.repository_id == candidate.repository_id &&
                  surface.target_branch == candidate.target_branch &&
                  surface.object_format == candidate.object_format &&
                  surface.head_commit_oid == candidate.head_commit_oid &&
                  surface.manifest_digest == candidate.manifest_digest &&
                  surface.build_context_digest == candidate.build_context_digest &&
                  surface.surface_digest == registration.surface_digest &&
                  candidate_reference?(
                    registration.surface_event,
                    "CandidateImpactSurfaceDerived",
                    candidate.candidate_id
                  )
        report.call(:surface, "must match the registered Candidate impact surface") unless matches
      end

      def validate_subject(evidence, report)
        registration = evidence.registration
        candidate = evidence.candidate
        expected = CandidateObligations::CandidateSubjectV1.new(
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
          registration_event: evidence.registration_event
        )
        report.call(:subject, "must preserve the exact registered evidence") unless evidence.subject == expected
      end

      def candidate_reference?(reference, type, candidate_id)
        reference &&
          reference.type == type &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "Candidate" &&
          reference.stream_id == candidate_id
      end
    end
  end
end
