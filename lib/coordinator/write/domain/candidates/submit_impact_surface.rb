# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Candidates
      class SubmitImpactSurface
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, derived_at:)
          denial = denied(state:, command:)
          return denial if denial

          submission = state.submission
          surface = command.surface
          event = Events::CandidateImpactSurfaceDerivedV1.new(
            candidate_id: command.candidate_id,
            change_set_id: submission.change_set_id,
            work_item_id: submission.work_item_id,
            attempt_id: submission.attempt_id,
            repository_id: submission.repository_id,
            target_branch: submission.target_branch,
            object_format: submission.object_format,
            head_commit_oid: submission.head_commit_oid,
            evidence_revision: 1,
            policy_version: surface.policy_version,
            surface_digest: surface.digest,
            manifest_digest: command.manifest_digest,
            build_context_digest: command.build_context_digest,
            produces: surface.produces,
            consumes: surface.consumes,
            may_affect: surface.may_affect,
            assumes: surface.assumes,
            analyzer: surface.analyzer,
            evidence_status: "attributed_unverified",
            derived_at:
          )
          Success(EventPlan.new(writes: [
            EventWrite.new(stream: @stream_factory.candidate(command.candidate_id), event:)
          ]))
        end

        private

        def denied(state:, command:)
          submission = state.submission
          return failure(:candidate_not_found, "Candidate does not exist", candidate_id: command.candidate_id) unless submission
          if submission.repository_id != command.repository_id || submission.head_commit_oid != command.head_commit_oid
            return failure(
              :candidate_impact_identity_mismatch,
              "Impact evidence does not identify the authoritative Candidate head",
              candidate_id: command.candidate_id,
              expected_repository_id: submission.repository_id,
              expected_head_commit_oid: submission.head_commit_oid,
              submitted_repository_id: command.repository_id,
              submitted_head_commit_oid: command.head_commit_oid
            )
          end
          unless state.manifest&.manifest_digest == command.manifest_digest && build_context_matches?(state, command)
            return failure(
              :candidate_impact_source_evidence_mismatch,
              "Impact evidence is not bound to the authoritative Candidate evidence",
              candidate_id: command.candidate_id,
              expected_manifest_digest: state.manifest&.manifest_digest,
              submitted_manifest_digest: command.manifest_digest,
              expected_build_context_digest: state.build_context&.build_context_digest,
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

        def build_context_matches?(state, command)
          return true unless command.build_context_digest

          state.build_context&.build_context_digest == command.build_context_digest
        end

        def failure(code, message, **details)
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
