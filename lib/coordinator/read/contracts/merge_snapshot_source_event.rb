# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class MergeSnapshotSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(:string, eql?: "MergeSnapshotRegistered")
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "MergeSnapshot")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, eql?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "merge-snapshot-registration/v1")
      end
    end
  end
end
