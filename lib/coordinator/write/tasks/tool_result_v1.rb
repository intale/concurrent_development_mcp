# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class ToolResultV1 < Value
      attribute :content, Types::Array.of(TextContentV1).constrained(min_size: 1, max_size: 10)
      attribute :is_error, Types::Strict::Bool
      attribute :structured_content, StructuredContentV1
    end
  end
end
