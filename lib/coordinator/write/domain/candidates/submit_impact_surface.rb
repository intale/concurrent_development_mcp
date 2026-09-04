# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Candidates
      class SubmitImpactSurface
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, surface_id:)
          denial = denied(state:, command:)
          return denial if denial

          evidence = state.evidence
          candidate = evidence.candidate
          surface = command.surface
          event = Events::CandidateImpactSurfaceDerivedV2.new(
            surface_id:,
            candidate_id: command.candidate_id,
            evidence_revision: 1,
            produces: surface.produces,
            consumes: surface.consumes,
            may_affect: surface.may_affect,
            assumes: surface.assumes
          )
          assignment = Events::CandidateImpactSurfaceAssignedV1.new(
            candidate_id: command.candidate_id,
            surface_id:
          )
          Success(EventPlan.new(writes: [
            EventWrite.new(stream: @stream_factory.candidate_impact_surface(surface_id), event:),
            EventWrite.new(
              stream: @stream_factory.candidate(command.candidate_id),
              event: assignment
            )
          ]))
        end

        private

        def denied(state:, command:)
          evidence = state.evidence
          return failure(:candidate_not_found, "Candidate does not exist", candidate_id: command.candidate_id) unless evidence

          candidate = evidence.candidate
          if candidate.repository_id != command.repository_id || candidate.head_commit_oid != command.head_commit_oid
            return failure(
              :candidate_impact_identity_mismatch,
              "Impact evidence does not identify the authoritative Candidate head",
              candidate_id: command.candidate_id,
              expected_repository_id: candidate.repository_id,
              expected_head_commit_oid: candidate.head_commit_oid,
              submitted_repository_id: command.repository_id,
              submitted_head_commit_oid: command.head_commit_oid
            )
          end
          unless candidate.manifest_digest == command.manifest_digest && build_context_matches?(evidence, command)
            return failure(
              :candidate_impact_source_evidence_mismatch,
              "Impact evidence is not bound to the authoritative Candidate evidence",
              candidate_id: command.candidate_id,
              expected_manifest_digest: candidate.manifest_digest,
              submitted_manifest_digest: command.manifest_digest,
              expected_build_context_digest: candidate.build_context_digest,
              submitted_build_context_digest: command.build_context_digest
            )
          end
          return unless state.existing_surface

          failure(
            :candidate_impact_surface_already_recorded,
            "Candidate already has an initial semantic-impact surface",
            candidate_id: command.candidate_id,
            existing_event: state.existing_surface.to_h
          )
        end

        def build_context_matches?(evidence, command)
          return true unless command.build_context_digest

          evidence.candidate.build_context_digest == command.build_context_digest
        end

        def failure(code, message, **details)
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
