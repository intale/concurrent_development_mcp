# frozen_string_literal: true

module Coordinator::Mcp
  module UsageSkills
    class Definition < Value
      attribute :name, Types::String
      attribute :description, Types::String
      attribute :instructions, Types::String
      attribute :tools, Types::Array.of(Types::String)
    end
  end
end
