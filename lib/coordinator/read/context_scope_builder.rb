# frozen_string_literal: true

module Coordinator::Read
  class ContextScopeBuilder
    def call(query, state)
      change_set = state.change_set
      return unless change_set

      case query.scope_kind
      when "change_set"
        ContextTokenDocument::ChangeSetScope.new(change_set_id: change_set.change_set_id)
      when "work_item"
        work_item = state.work_items.find { _1.work_item_id == query.scope_id }
        return unless work_item

        ContextTokenDocument::WorkItemScope.new(
          change_set_id: change_set.change_set_id,
          work_item_id: work_item.work_item_id
        )
      when "attempt"
        attempt = state.attempts.find { _1.attempt_id == query.scope_id }
        return unless attempt

        ContextTokenDocument::AttemptScope.new(
          change_set_id: change_set.change_set_id,
          work_item_id: attempt.work_item_id,
          attempt_id: attempt.attempt_id
        )
      end
    end
  end
end
