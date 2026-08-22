# frozen_string_literal: true

module Coordinator::Read
  class ProjectionScopeRoot < Value
    attribute :scope_kind, Types::String.enum("change_set", "work_item", "attempt")
    attribute :scope_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
  end
end
