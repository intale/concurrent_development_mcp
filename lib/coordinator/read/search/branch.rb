# frozen_string_literal: true

module Coordinator::Read::Search
  class Branch < Coordinator::Read::Value
    attribute :field, Field
    attribute :expression, Node
  end
end
