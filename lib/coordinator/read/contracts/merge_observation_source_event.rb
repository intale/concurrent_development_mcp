# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class MergeObservationSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(
          :string,
          included_in?: %w[MergeObserved MergeObservationAuthorizationLinked]
        )
        required(:schema_version).filled(:integer, included_in?: [ 1, 2 ])
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "MergeSnapshot")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 3)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "merge-observation/v1")
      end


      rule(:event_type, :schema_version) do
        expected = values[:event_type] == "MergeObserved" ? 2 : 1
        key(:schema_version).failure("must match the exact observation fact") unless values[:schema_version] == expected
      end
    end
  end
end
