# frozen_string_literal: true

module Coordinator::Read
  class ContextNextActionsBuilder
    def call(state)
      change_set = state.change_set
      return [] unless change_set

      if change_set.status == "planning"
        return [
          NextAction.new(
            tool: "work_item_create",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: change_set.change_set_id)
          ),
          NextAction.new(
            tool: "change_set_activate",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: change_set.change_set_id)
          )
        ].freeze
      end

      ready_actions = state.work_items.select { _1.status == "ready" }.map do |work_item|
        NextAction.new(
          tool: "work_item_acquire",
          arguments: NextAction::WorkItemArguments.new(
            change_set_id: change_set.change_set_id,
            work_item_id: work_item.work_item_id
          )
        )
      end
      attempt_actions = state.attempts.select { _1.status == "started" }.map do |attempt|
        NextAction.new(
          tool: "write_set_reserve",
          arguments: NextAction::AttemptArguments.new(
            change_set_id: change_set.change_set_id,
            work_item_id: attempt.work_item_id,
            attempt_id: attempt.attempt_id
          )
        )
      end

      (ready_actions + attempt_actions).freeze
    end
  end
end
