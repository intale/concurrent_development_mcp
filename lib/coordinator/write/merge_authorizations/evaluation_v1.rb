# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class EvaluationV1 < Value
      Candidate = CandidateEvidenceReferenceV1
      Obligation = ObligationCheckV1
      Reason = ReasonV1
      Progress = WorkItemProgressV1

      attribute :merge_snapshot_id, Types::Identifier
      attribute :snapshot, SnapshotEvidenceV1.optional
      attribute :target_base_observation, TargetBaseObservationV1
      attribute :current_policy, CurrentImpactPolicyV1.optional
      attribute :candidates,
                Types::Array.of(Candidate).constrained(max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :work_item_progress,
                Types::Array.of(Progress).constrained(max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :obligations,
                Types::Array.of(Obligation).constrained(max_size: Types::MERGE_AUTHORIZATION_MAXIMUM_OBLIGATIONS)
      attribute :reasons,
                Types::Array.of(Reason).constrained(max_size: Types::MERGE_AUTHORIZATION_MAXIMUM_REASONS)

      def granted?
        reasons.empty?
      end
    end
  end
end
