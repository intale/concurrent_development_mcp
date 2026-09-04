# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class ProgressPreparationV1 < Value
      attribute :event_id, Types::UuidV7
      attribute :correlation_id, Types::UuidV7
    end
  end
end
