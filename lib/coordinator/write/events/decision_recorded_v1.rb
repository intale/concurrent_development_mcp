# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionRecordedV1 < Base
      contract type: "DecisionRecorded", version: 1

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :source_event, EventReference
      attribute :proposal_event, EventReference
      attribute :acceptance_event, EventReference
      attribute :definition, Decisions::DecisionDefinitionV1
      attribute :classifier, Interpretations::ClassifierAttributionV1
      attribute :scope_provenance, Interpretations::DecisionScopeProvenanceV1
      attribute :recorded_at, Types::Timestamp
    end
  end
end
