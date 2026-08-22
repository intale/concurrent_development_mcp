# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Interpretations
      class AdjudicationState < Value
        attribute :proposal, Coordinator::Write::Interpretations::InterpretationProposalEvidenceV1.optional
        attribute :terminal, Coordinator::Write::Interpretations::InterpretationTerminalEvidenceV1.optional
        attribute :slot_acceptance, Coordinator::Write::Interpretations::InterpretationTerminalEvidenceV1.optional
      end
    end
  end
end
