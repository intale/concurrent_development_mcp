# frozen_string_literal: true

module Coordinator::Read::Search
  class Node < Coordinator::Read::Value
    attribute :operator, Coordinator::Read::Types::String.optional
    attribute :operands, Coordinator::Read::Types::Array.of(Coordinator::Read::Types.Instance(self))
    attribute :match, Coordinator::Read::Types::String.optional
    attribute :value, Coordinator::Read::Types::String.optional
    attribute :case_sensitive, Coordinator::Read::Types::Bool
  end
end
