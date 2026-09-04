# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class ReleaseSetSourceEvent < Dry::Validation::Contract
      EVENT_SCHEMAS = {
        "ReleaseSetCreated" => [ 1, "release-set-preparation/v1" ],
        "ReleaseSetMemberAdded" => [ 1, "release-set-preparation/v1" ],
        "ReleaseSetPrepared" => [ 2, "release-set-preparation/v1" ],
        "RepositoryIntegrationRecorded" => [ 2, "release-set-integration/v1" ],
        "RepositoryIntegrationMergeLinked" => [ 1, "release-set-integration/v1" ],
        "ReleaseSetVerificationRecorded" => [ 2, "release-set-verification/v1" ],
        "ReleaseSetIntegrationLinked" => [ 1, "release-set-verification/v1" ],
        "ReleaseSetActivated" => [ 2, "release-set-activation/v1" ],
        "ReleaseSetCompensationRequested" => [ 2, "release-set-compensation/v1" ],
        "ReleaseSetSuccessfulIntegrationLinked" => [ 1, "release-set-compensation/v1" ],
        "ReleaseSetOutcomeRecorded" => [ 1, "release-set-completion/v1" ],
        "ReleaseSetCompleted" => [ 2, "release-set-completion/v1" ]
      }.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_SCHEMAS.keys)
        required(:schema_version).filled(:integer)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "ReleaseSet")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, included_in?: %w[agent system])
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string)
      end

      rule(:event_type, :schema_version, :policy_version) do
        expected_schema, expected_policy = EVENT_SCHEMAS.fetch(values[:event_type])
        key(:schema_version).failure("does not match event_type") unless values[:schema_version] == expected_schema
        key(:policy_version).failure("does not match event_type") unless values[:policy_version] == expected_policy
      end

      rule(:event_type, :actor_kind) do
        allowed = case values[:event_type]
        when "ReleaseSetCompensationRequested", "ReleaseSetSuccessfulIntegrationLinked" then [ "system" ]
        when "ReleaseSetOutcomeRecorded", "ReleaseSetCompleted" then %w[agent system]
        else [ "agent" ]
        end
        key(:actor_kind).failure("actor_kind does not match event_type") unless allowed.include?(values[:actor_kind])
      end
    end
  end
end
