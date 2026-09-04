# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionRecordedV2 < Base
      contract type: "DecisionRecorded", version: 2

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :definition, Decisions::DecisionDefinitionDocumentV1
    end
  end
end
