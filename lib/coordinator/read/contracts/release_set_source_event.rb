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
          ]
        )
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "ReleaseSet")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(
          :string,
          included_in?: %w[
            release-set-preparation/v1 release-set-integration/v1 release-set-verification/v1
          ]
        )
      end


      rule(:event_type, :stream_revision, :policy_version) do
        expected = {
          "ReleaseSetPrepared" => [ "release-set-preparation/v1", 0 ],
          "RepositoryIntegrationRecorded" => [ "release-set-integration/v1", 1 ],
          "ReleaseSetVerificationRecorded" => [ "release-set-verification/v1", 1 ]
        }.fetch(values[:event_type])
        key.failure("policy_version does not match event_type") unless values[:policy_version] == expected.first
        minimum_revision = expected.last
        if values[:event_type] == "ReleaseSetPrepared"
          key.failure("preparation must be the first stream event") unless values[:stream_revision] == minimum_revision
        elsif values[:stream_revision] < minimum_revision
          key.failure("lifecycle event revision is invalid")
        end
      end
    end
  end
end
