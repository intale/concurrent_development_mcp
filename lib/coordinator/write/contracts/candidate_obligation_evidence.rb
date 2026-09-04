# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateObligationEvidence < Dry::Validation::Contract
      params do
        required(:evidence).value(Types.Instance(CandidateObligations::CandidateEvidenceV2))
      end

      rule(:evidence) do
        evidence = value
        candidate = evidence.candidate
        assignment = evidence.registration
        surface = evidence.surface
        report = ->(field, message) { key([ :evidence, field ]).failure(message) }

        unless assignment.candidate_id == candidate.candidate_id &&
               assignment.surface_id == surface.surface_id
          report.call(:registration, "must assign the loaded surface to the loaded Candidate")
        end
        unless candidate.surface_id == surface.surface_id &&
               candidate.surface_assignment_event == evidence.registration_event
          report.call(:candidate, "must retain the exact surface assignment")
        end
        unless valid_assignment_reference?(evidence.registration_event, candidate)
          report.call(:registration_event, "must identify the exact Candidate assignment fact")
        end
        unless valid_surface_reference?(evidence.surface_event, surface)
          report.call(:surface_event, "must identify the exact immutable impact surface")
        end
        unless surface.candidate_id == candidate.candidate_id
          report.call(:surface, "must belong to the loaded Candidate")
        end
        validate_subject(evidence, report)
      end

      private

      def validate_subject(evidence, report)
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
          surface_digest: evidence.surface_digest,
          candidate_event: candidate.submission_event,
          manifest_event: candidate.manifest_event,
          build_context_event: candidate.build_context_event,
          surface_event: evidence.surface_event,
          registration_event: evidence.registration_event
        )
        report.call(:subject, "must preserve the exact cohesive Candidate evidence") unless evidence.subject == expected
      end

      def valid_assignment_reference?(reference, candidate)
        reference.type == "CandidateImpactSurfaceAssigned" &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "Candidate" &&
          reference.stream_id == candidate.candidate_id
      end

      def valid_surface_reference?(reference, surface)
        reference.type == "CandidateImpactSurfaceDerived" &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "CandidateImpactSurface" &&
          reference.stream_id == surface.surface_id
      end
    end
  end
end
