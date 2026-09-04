# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class PreparationFactV2 < Value
      attribute :payload, PreparedStateV2
      attribute :event, EventReference
      attribute :correlation_id, Types::UuidV7
    end
  end
end
