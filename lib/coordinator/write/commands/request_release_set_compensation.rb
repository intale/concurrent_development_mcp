# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RequestReleaseSetCompensation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :release_set_id, Types::Identifier
      attribute :trigger_event, EventReference
      attribute :rule_version, Types::ReleaseSetCompensationRuleVersion
    end
  end
end
