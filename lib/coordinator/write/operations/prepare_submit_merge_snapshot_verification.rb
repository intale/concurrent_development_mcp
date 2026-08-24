# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareSubmitMergeSnapshotVerification < Dry::Operation
      POLICY_VERSION = "merge-snapshot-verification/v1"

      def initialize(contract: Contracts::SubmitMergeSnapshotVerification.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        binding = attributes.fetch(:binding)
        assessment = attributes.fetch(:assessment)
        Commands::SubmitMergeSnapshotVerification.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          merge_snapshot_id: attributes.fetch(:merge_snapshot_id),
          binding: MergeSnapshotVerifications::BindingV1.new(
            snapshot_event: EventReference.new(binding.fetch(:snapshot_event)),
            snapshot_digest: binding.fetch(:snapshot_digest),
            repository_id: binding.fetch(:repository_id),
            target_branch: binding.fetch(:target_branch),
            object_format: binding.fetch(:object_format),
            target_base_commit_oid: binding.fetch(:target_base_commit_oid),
            ordered_candidates: binding.fetch(:ordered_candidates).map do |candidate|
              MergeSnapshotVerifications::BindingCandidateV1.new(candidate)
            end,
            merge_commit_oid: binding.fetch(:merge_commit_oid)
          ),
          assessment: MergeSnapshotVerifications::AssessmentV1.new(
            evidence_kind: assessment.fetch(:evidence_kind),
            producer: MergeSnapshotVerifications::ProducerV1.new(assessment.fetch(:producer)),
            run_id: assessment.fetch(:run_id),
            test_suite_digest: assessment.fetch(:test_suite_digest),
            environment_digest: assessment.fetch(:environment_digest),
            result_digest: assessment.fetch(:result_digest),
            conclusion: assessment.fetch(:conclusion),
            findings: assessment.fetch(:findings).map do |finding|
              MergeSnapshotVerifications::FindingV1.new(finding)
            end,
            produced_at: assessment.fetch(:produced_at)
          ),
          policy_version: POLICY_VERSION
        )
      end

      private

      def invalid(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "SubmitMergeSnapshotVerification input is invalid",
            details:
          )
        )
      end
    end
  end
end
