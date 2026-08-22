# frozen_string_literal: true

module Coordinator::Write
  class InterpretationProposalPreparationV1 < Value
    attribute :proposed_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :proposal_event_id, Types::UuidV7
    attribute :clarification_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
  end
end
