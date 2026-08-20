# frozen_string_literal: true

module Coordinator
  module Mcp
    class Settings < Value
      attribute :allowed_hosts, Types::Array.of(Types::String).constrained(max_size: 100)
      attribute :allowed_origins, Types::Array.of(Types::String).constrained(max_size: 100)
      attribute :max_request_bytes, Types::Integer.constrained(gteq: 1, lteq: 67_108_864)
    end
  end
end
