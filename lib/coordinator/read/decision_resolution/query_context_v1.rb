# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class QueryContextV1 < Value
      Path = Types::ResourcePath

      attribute :workspace_id, Types::Identifier.optional
      attribute :repository_id, Types::RepositoryId
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :phase, Types::DecisionPhase
      attribute :language, Types::Identifier
      attribute :paths, Types::Array.of(Path).constrained(max_size: 32)
      attribute :environment, Types::Identifier.optional
      attribute :agent_role, Types::Identifier
    end
  end
end
