# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactSurfaceEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::SubmitCandidateImpactSurface))
        required(:state).value(Types.Instance(Domain::Candidates::ImpactSurfaceState))
        required(:surface_event).value(Types.Instance(EventReference))
        required(:derived_at).filled(:string)
      end

      rule(:plan, :command, :state, :surface_event, :derived_at) do
        evidence = values[:state].evidence
        submission = evidence.submission
        command = values[:command]
        surface = command.surface
        expected = Events::CandidateImpactSurfaceDerivedV1.new(
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
          derived_at: values[:derived_at]
        )
        registration = Events::CandidateImpactSurfaceRegisteredV1.new(
          candidate_id: command.candidate_id,
          change_set_id: submission.change_set_id,
          work_item_id: submission.work_item_id,
          attempt_id: submission.attempt_id,
          repository_id: submission.repository_id,
          target_branch: submission.target_branch,
          object_format: submission.object_format,
          base_commit_oid: submission.base_commit_oid,
          head_commit_oid: submission.head_commit_oid,
          candidate_event: evidence.submission_event,
          manifest_event: evidence.manifest_event,
          build_context_event: evidence.build_context_event,
          surface_event: values[:surface_event],
          surface_digest: surface.digest,
          index_policy_version: Coordinator::Write::Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION,
          registered_at: values[:derived_at]
        )
        expected_stream = StreamFactory.new.candidate(command.candidate_id)
        expected_registry = StreamFactory.new.candidate_impact_registry(submission.change_set_id)
        plan = values[:plan]
        unless plan.events == [ expected, registration ] &&
               plan.writes.map(&:stream) == [ expected_stream, expected_registry ]
          key(:plan).failure("must preserve the exact Candidate surface and ChangeSet registry facts")
        end
      end
    end
  end
end
