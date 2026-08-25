# frozen_string_literal: true

module Coordinator::Read
  class ContextNextActionsBuilder
    def call(state)
      change_set = state.change_set
      return [] unless change_set
      return [] if change_set.status == "completed"

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
      attempt_actions = state.attempts.select do |attempt|
        attempt.status == "started" && attempt.write_set.nil?
      end.map do |attempt|
        NextAction.new(
          tool: "write_set_reserve",
          arguments: NextAction::AttemptArguments.new(
            change_set_id: change_set.change_set_id,
            work_item_id: attempt.work_item_id,
            attempt_id: attempt.attempt_id
          )
        )
      end

      completion_actions = state.work_items.filter_map do |work_item|
        completion_action(state, change_set, work_item)
      end

      (ready_actions + attempt_actions + completion_actions).freeze
    end

    private

    def completion_action(state, change_set, work_item)
      return unless work_item.status == "acquired"

      attempt = state.attempts.find { _1.attempt_id == work_item.active_attempt_id }
      checkpoint = state.candidate_checkpoints.find { _1.attempt_id == work_item.active_attempt_id }
      return unless attempt&.status == "started"
      return unless attempt.write_set&.released_at
      return unless checkpoint&.checkpoint_kind == "final"

      NextAction.new(
        tool: "work_item_complete",
        arguments: NextAction::WorkItemCompletionArguments.new(
          change_set_id: change_set.change_set_id,
          work_item_id: work_item.work_item_id,
          attempt_id: attempt.attempt_id,
          candidate_id: checkpoint.candidate_id
        )
      )
    end
  end
end
