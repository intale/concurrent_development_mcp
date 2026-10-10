# frozen_string_literal: true

module Coordinator::Read::Search
  class ExpressionValidation < Coordinator::Read::Value
    attribute :node_count, Coordinator::Read::Types::Integer
    attribute :issues, Coordinator::Read::Types::Array.of(ExpressionIssue)
  end
end
