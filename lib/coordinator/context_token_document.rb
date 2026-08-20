# frozen_string_literal: true

module Coordinator
  class ContextTokenDocument < Value
    class ChangeSetScope < Value
      attribute :change_set_id, Types::Identifier
    end

    class WorkItemScope < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class AttemptScope < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    Scope = ChangeSetScope | WorkItemScope | AttemptScope

    attribute :schema, Types::String.enum("context-token/v1")
    attribute :scope, Scope
    attribute :projection_barriers, ProjectionBarriers
  end
end
