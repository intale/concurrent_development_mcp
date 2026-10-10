# frozen_string_literal: true

module Coordinator::Read::Search
  class Document < Coordinator::Read::Value
    attribute :entity_type, Coordinator::Read::Types::String
    attribute :document_id, Coordinator::Read::Types::String
    attribute :entity_id, Coordinator::Read::Types::String.optional
    attribute :updated_at, Coordinator::Read::Types::Timestamp
    attribute :scope, Coordinator::Read::Types::String.optional
    attribute :repository_id, Coordinator::Read::Types::String.optional
    attribute :retrieval, Coordinator::Read::Types::Hash.optional
    attribute :provenance, Coordinator::Read::Types::Hash
    attribute :matches, Coordinator::Read::Types::Array.of(Evidence).constrained(max_size: Limits::FIELDS)
  end
end
