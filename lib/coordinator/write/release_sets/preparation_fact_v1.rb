# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class PreparationFactV1 < Value
      attribute :payload, Events::ReleaseSetPreparedV1
      attribute :event, EventReference
      attribute :correlation_id, Types::UuidV7
    end
  end
end
