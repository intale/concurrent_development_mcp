# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  class Page < Coordinator::Shared::Value
    attribute :items, Coordinator::Shared::Types::Array.of(Summary).constrained(max_size: 100)
    attribute :next_skill_id, Coordinator::Shared::Types::String.optional
    attribute :has_more, Coordinator::Shared::Types::Bool
  end
end
