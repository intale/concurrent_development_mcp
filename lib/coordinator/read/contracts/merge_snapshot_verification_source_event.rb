# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class MergeSnapshotVerificationSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: %w[
          MergeSnapshotVerificationSubmitted
          MergeSnapshotVerificationAssigned
          MergeSnapshotVerificationSelected
          MergeSnapshotVerified
        ])
        required(:schema_version).filled(:integer, included_in?: [ 1, 2 ])
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, included_in?: %w[MergeSnapshot MergeVerification])
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, included_in?: %w[agent system])
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "merge-snapshot-verification/v1")
      end

      rule(:event_type, :schema_version, :stream_name, :actor_kind) do
        expected = {
          "MergeSnapshotVerificationSubmitted" => [ 2, "MergeVerification", "agent" ],
          "MergeSnapshotVerificationAssigned" => [ 1, "MergeSnapshot", "agent" ],
          "MergeSnapshotVerificationSelected" => [ 1, "MergeSnapshot", "system" ],
          "MergeSnapshotVerified" => [ 2, "MergeSnapshot", "system" ]
        }.fetch(values[:event_type])
        actual = values.values_at(:schema_version, :stream_name, :actor_kind)
        key.failure("must match the exact verification fact source") unless actual == expected
      end
    end
  end
end
