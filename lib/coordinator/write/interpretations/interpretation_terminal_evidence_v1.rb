# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationTerminalEvidenceV1 < Value
      attribute :status, Types::String.enum("accepted", "rejected")
      attribute :interpretation_id, Types::Identifier
      attribute :event, EventReference
    end
  end
end
