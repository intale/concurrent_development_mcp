# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CompleteActivatedReleaseSet < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :release_set_id, Types::Identifier
      attribute :activation_event, EventReference
      attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
    end
  end
end
