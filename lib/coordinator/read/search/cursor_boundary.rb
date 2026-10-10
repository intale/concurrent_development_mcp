# frozen_string_literal: true

module Coordinator::Read::Search
  class CursorBoundary < Coordinator::Read::Value
    attribute :updated_at, Coordinator::Read::Types::Timestamp
    attribute :entity_type, Coordinator::Read::Types::String
    attribute :document_id, Coordinator::Read::Types::String
  end
end
