# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  class Summary < Coordinator::Shared::Value
    attribute :source, Coordinator::Shared::Types::String.enum("server")
    attribute :skill_id, Coordinator::Shared::Types::String
    attribute :name, Coordinator::Shared::Types::String
    attribute :scope, Coordinator::Shared::Types::String
    attribute :revision, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
    attribute :description, Coordinator::Shared::Types::String
    attribute :tools, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
  end
end
