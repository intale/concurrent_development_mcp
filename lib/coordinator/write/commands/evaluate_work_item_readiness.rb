# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class EvaluateWorkItemReadiness < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :source_activation_event_id, Types::UuidV7
      attribute :source_activation_revision, Types::Integer.constrained(gteq: 0)
      attribute :policy_version, Types::String.enum("change-set-readiness/v1")
      attribute :decision_identity, Types.Instance(ReadinessDecisionIdentity)

      def readiness_decision_id
        decision_identity.readiness_decision_id
      end

      def process_decision_marker
        decision_identity.compound_marker.marker
      end

      def process_decision_components
        decision_identity.compound_marker.components
      end
    end
  end
end
