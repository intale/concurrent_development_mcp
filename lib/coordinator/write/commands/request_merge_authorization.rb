# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RequestMergeAuthorization < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :merge_snapshot_id, Types::Identifier
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
      attribute :target_base_observation, MergeAuthorizations::TargetBaseObservationV1
      attribute :expected_impact_policy, MergeAuthorizations::ExpectedImpactPolicyV1.optional
      attribute :policy_version, Types::MergeAuthorizationPolicyVersion
    end
  end
end
