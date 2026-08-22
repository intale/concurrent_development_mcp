# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionScopeV1 < Value
      attribute :workspace_id, Types::Identifier.optional
      attribute :repository_ids, Types::ScopeRepositoryIds
      attribute :branch_selectors, Types::ScopeIdentifiers
      attribute :change_set_id, Types::Identifier.optional
      attribute :work_item_id, Types::Identifier.optional
      attribute :attempt_id, Types::Identifier.optional
      attribute :candidate_id, Types::Identifier.optional
      attribute :path_selectors, Types::ScopePaths
      attribute :symbol_selectors, Types::ScopeIdentifiers
      attribute :contract_selectors, Types::ScopeIdentifiers
      attribute :schema_selectors, Types::ScopeIdentifiers
      attribute :environments, Types::ScopeIdentifiers
      attribute :agent_roles, Types::ScopeIdentifiers
    end
  end
end
