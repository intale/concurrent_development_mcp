# frozen_string_literal: true

module Coordinator
  class ProjectionScopeRootsBuilder
    def call(event)
      roots = [
        ProjectionScopeRoot.new(
          scope_kind: "change_set",
          scope_id: event.change_set_id,
          change_set_id: event.change_set_id
        )
      ]

      case event
      when Events::WorkItemCreatedV1,
           Events::WorkItemAddedToChangeSetV1,
           Events::WorkItemMadeReadyV1,
           Events::WorkItemAcquiredV1,
           Events::AttemptAuthorizedV1,
           Events::AttemptStartedV1
        roots << ProjectionScopeRoot.new(
          scope_kind: "work_item",
          scope_id: event.work_item_id,
          change_set_id: event.change_set_id
        )
      end

      case event
      when Events::AttemptAuthorizedV1, Events::AttemptStartedV1
        roots << ProjectionScopeRoot.new(
          scope_kind: "attempt",
          scope_id: event.attempt_id,
          change_set_id: event.change_set_id
        )
      end

      roots.freeze
    end
  end
end
