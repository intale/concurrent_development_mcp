# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetCompensationRequestViewV1 < Value
    attribute :trigger_event, Coordinator::Write::EventReference.optional
    attribute :trigger_kind, Types::ReleaseSetCompensationTriggerKind
    attribute :successful_integrations,
              Types::Array.of(Coordinator::Write::EventReference)
                .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
    attribute :reason, Types::ReleaseSetEvidenceSummary
    attribute :rule_version, Types::ReleaseSetCompensationRuleVersion
    attribute :requested_at, Types::Timestamp
    attribute :source, ReleaseSetSourceEvidenceV1
  end
end
