# frozen_string_literal: true

module Coordinator::Write
  class VerificationObligationWaiverPreparationV1 < Value
    attribute :waived_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :waiver_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
