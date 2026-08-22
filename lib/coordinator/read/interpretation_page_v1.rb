# frozen_string_literal: true

module Coordinator::Read
  class InterpretationPageV1 < Value
    Proposal = InterpretationProposalV1

    attribute :message_id, Types::Identifier
    attribute :interpretations, Types::Array.of(Proposal).constrained(max_size: 100)
    attribute :next_after_revision, Types::StreamRevisionCursor.optional
  end
end
