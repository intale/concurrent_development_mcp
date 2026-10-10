# frozen_string_literal: true

module Coordinator::Read::Search
  class Evidence < Coordinator::Read::Value
    attribute :field, Coordinator::Read::Types::String.enum(*FieldCatalog::SELECTORS)
    attribute :path, Coordinator::Read::Types::Array.of(Coordinator::Read::Types::String)
    attribute :excerpt, Coordinator::Read::Types::String.constrained(max_size: Limits::EXCERPT_CHARACTERS)
    attribute :excerpt_offset, Coordinator::Read::Types::Integer.constrained(gteq: 0)
  end
end
