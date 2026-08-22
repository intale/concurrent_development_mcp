# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TextContentV1 < Value
      attribute :type, Types::String.enum("text")
      attribute :text, Types::String.constrained(min_size: 1, max_size: 100_000)
    end
  end
end
