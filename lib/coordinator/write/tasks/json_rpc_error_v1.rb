# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class JsonRpcErrorV1 < Value
      attribute :code, Types::Integer
      attribute :message, Types::String.constrained(min_size: 1, max_size: 4_000)
    end
  end
end
