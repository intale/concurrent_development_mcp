# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CompleteCompensatedReleaseSet < Value
      Evidence = ReleaseSets::CompensationEvidenceV2

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :release_set_id, Types::Identifier
      attribute :compensation_request_event, EventReference
      attribute :evidence,
                Types::Array.of(Evidence)
                  .constrained(min_size: 1, max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
    end
  end
end
