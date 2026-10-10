# frozen_string_literal: true

module Coordinator::Read::Search
  class ExpressionIssue < Coordinator::Read::Value
    attribute :path, Coordinator::Read::Types::Array.of(Coordinator::Read::Types::String | Coordinator::Read::Types::Integer)
    attribute :message, Coordinator::Read::Types::String
  end
end
