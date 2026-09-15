# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TransformationErrorV1 < Value
      attribute :code, Types::Symbol.enum(:unsupported_source_contract, :invalid_source_event)
      attribute :message, Types::String
      attribute :event_type, Types::String.constrained(min_size: 1, max_size: 255)
      attribute :schema_version, Types::Integer.optional
      attribute :source_event_id, Types::String.constrained(min_size: 1, max_size: 255)
    end
  end
end
