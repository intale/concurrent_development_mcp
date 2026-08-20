# frozen_string_literal: true

module Coordinator
  class OutcomeError < Value
    attribute :code, Types::Symbol
    attribute :message, Types::String
    attribute :details, Types::Hash
  end
end
