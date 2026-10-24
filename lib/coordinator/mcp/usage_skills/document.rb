# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  class Document < Summary
    attribute :instructions, Coordinator::Shared::Types::String
    attribute :assets, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String).constrained(size: 0)
  end
end
