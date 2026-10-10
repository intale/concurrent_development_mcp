# frozen_string_literal: true

module Coordinator::Read::Search
  class Problem < Coordinator::Read::Value
    attribute :code, Coordinator::Read::Types::String
    attribute :message, Coordinator::Read::Types::String
    attribute :details, Coordinator::Read::Types::Hash
  end
end
