# frozen_string_literal: true

module Coordinator::Mcp
  module UsageSkills
    class InstallationResult < Value
      attribute :name, Types::String
      attribute :revision, Types::Integer
      attribute :outcome, Types::String.enum("published", "existing")
      attribute :task_id, Types::TaskId
    end
  end
end
