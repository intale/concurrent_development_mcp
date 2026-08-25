# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CompleteChangeSet < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :source_event, EventReference
      attribute :release_set_id, Types::Identifier.optional
      attribute :rule_version, Types::String.enum("change-set-completion/v1")
      attribute :decision_identity, ChangeSetCompletionDecisionIdentity

      def process_decision_marker
        decision_identity.compound_marker.marker
      end

      def process_decision_components
        decision_identity.compound_marker.components
      end
    end
  end
end
