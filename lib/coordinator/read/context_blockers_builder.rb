# frozen_string_literal: true

module Coordinator::Read
  class ContextBlockersBuilder
    def call(scope, state)
      dependencies = if scope.is_a?(ContextTokenDocument::ChangeSetScope)
        state.dependencies
      else
        state.dependencies.select { _1.consumer_work_item_id == scope.work_item_id }
      end

      dependencies.reject { _1.satisfied_at }.map do |dependency|
        ContextBlockerV1.new(
          code: "dependency_unmet",
          dependency_id: dependency.dependency_id,
          producer_work_item_id: dependency.producer_work_item_id,
          consumer_work_item_id: dependency.consumer_work_item_id,
          dependency_kind: dependency.dependency_kind
        )
      end.freeze
    end
  end
end
