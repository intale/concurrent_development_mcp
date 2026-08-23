# frozen_string_literal: true

module Coordinator::Write
  class AgentChoiceImpactScanProgressPreparationV1 < Value
    attribute :progressed_at, Types::Timestamp
    attribute :event_id, Types::UuidV7
  end
end
