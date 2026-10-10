# frozen_string_literal: true

module Coordinator::Read::Search
  class Document < Coordinator::Read::Value
    attribute :entity_type, Coordinator::Read::Types::String.enum(*FieldCatalog::ENTITY_TYPES)
    attribute :document_id, Coordinator::Read::Types::String
    attribute :entity_id, Coordinator::Read::Types::String.optional
    attribute :updated_at, Coordinator::Read::Types::Timestamp
    attribute :scope, Coordinator::Read::Types::String.optional
    attribute :repository_id, Coordinator::Read::Types::String.optional
    attribute :retrieval_actions, Coordinator::Read::Types::Array.of(Retrieval::Type).constrained(max_size: 2)
    attribute :provenance, Provenance
    attribute :matches, Coordinator::Read::Types::Array.of(Evidence).constrained(max_size: Limits::FIELDS)
  end
end
