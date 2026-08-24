# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetCompensationRequestedV1 < Base
      contract type: "ReleaseSetCompensationRequested", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :trigger_event, EventReference
      attribute :trigger_kind, Types::ReleaseSetCompensationTriggerKind
      attribute :successful_integrations,
                Types::Array.of(EventReference)
                  .constrained(min_size: 1, max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :reason, Types::ReleaseSetEvidenceSummary
      attribute :rule_version, Types::ReleaseSetCompensationRuleVersion
      attribute :requested_at, Types::Timestamp
    end
  end
end
