# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class ReleaseSetSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(
          :string,
          included_in?: %w[
            ReleaseSetPrepared RepositoryIntegrationRecorded ReleaseSetVerificationRecorded
            ReleaseSetActivated ReleaseSetCompensationRequested ReleaseSetCompleted
          ]
        )
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "ReleaseSet")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, included_in?: %w[agent system])
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(
          :string,
          included_in?: %w[
            release-set-preparation/v1 release-set-integration/v1 release-set-verification/v1
            release-set-activation/v1 release-set-compensation/v1 release-set-completion/v1
          ]
        )
      end

      rule(:event_type, :stream_revision, :policy_version) do
        expected = {
          "ReleaseSetPrepared" => [ "release-set-preparation/v1", 0 ],
          "RepositoryIntegrationRecorded" => [ "release-set-integration/v1", 1 ],
          "ReleaseSetVerificationRecorded" => [ "release-set-verification/v1", 1 ],
          "ReleaseSetActivated" => [ "release-set-activation/v1", 1 ],
          "ReleaseSetCompensationRequested" => [ "release-set-compensation/v1", 1 ],
          "ReleaseSetCompleted" => [ "release-set-completion/v1", 1 ]
        }.fetch(values[:event_type])
        key.failure("policy_version does not match event_type") unless values[:policy_version] == expected.first
        minimum_revision = expected.last
        if values[:event_type] == "ReleaseSetPrepared"
          key.failure("preparation must be the first stream event") unless values[:stream_revision] == minimum_revision
        elsif values[:stream_revision] < minimum_revision
          key.failure("lifecycle event revision is invalid")
        end
      end

      rule(:event_type, :actor_kind) do
        allowed = case values[:event_type]
        when "ReleaseSetCompensationRequested" then [ "system" ]
        when "ReleaseSetCompleted" then %w[agent system]
        else [ "agent" ]
        end
        key(:actor_kind).failure("actor_kind does not match event_type") unless allowed.include?(values[:actor_kind])
      end
    end
  end
end
