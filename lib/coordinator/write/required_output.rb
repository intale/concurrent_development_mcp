# frozen_string_literal: true

module Coordinator::Write
  class RequiredOutput < Value
    attribute :kind, Types::Identifier
    attribute :key, Types::Identifier
  end
end
