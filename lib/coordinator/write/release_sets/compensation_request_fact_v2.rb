# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CompensationRequestFactV2 < Value
      attribute :payload, Events::ReleaseSetCompensationRequestedV2
      attribute :event, EventReference
      attribute :successful_integrations,
                Types::Array.of(EventReference)
                  .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :integration_link_events,
                Types::Array.of(EventReference)
                  .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :release_digest, Types::Sha256Digest
      attribute :rule_version, Types::ReleaseSetCompensationRuleVersion
    end
  end
end
