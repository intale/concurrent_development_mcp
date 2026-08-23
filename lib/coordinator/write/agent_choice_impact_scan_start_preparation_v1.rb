# frozen_string_literal: true

module Coordinator::Write
  class AgentChoiceImpactScanStartPreparationV1 < Value
    attribute :started_at, Types::Timestamp
    attribute :event_id, Types::UuidV7
  end
end
