# frozen_string_literal: true

module Coordinator::Read
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
      when Coordinator::Write::Events::WorkItemCreatedV1,
           Coordinator::Write::Events::WorkItemAddedToChangeSetV1,
           Coordinator::Write::Events::WorkItemMadeReadyV1,
           Coordinator::Write::Events::WorkItemAcquiredV1,
           Coordinator::Write::Events::AttemptAuthorizedV1,
           Coordinator::Write::Events::AttemptStartedV1,
           Coordinator::Write::Events::WriteSetReservedV2,
           Coordinator::Write::Events::WriteSetExpandedV2,
           Coordinator::Write::Events::WriteSetRenewedV2,
           Coordinator::Write::Events::WriteSetReleasedV2,
           Coordinator::Read::CandidateSubmissionViewV2,
           Coordinator::Write::Events::WorkItemCandidateSelectedV1,
           Coordinator::Write::Events::WorkItemCompletedV1,
           Coordinator::Write::Events::AttemptCompletedV1
        roots << ProjectionScopeRoot.new(
          scope_kind: "work_item",
          scope_id: event.work_item_id,
          change_set_id: event.change_set_id
        )
      end

      case event
      when Coordinator::Write::Events::AttemptAuthorizedV1,
           Coordinator::Write::Events::AttemptStartedV1,
           Coordinator::Write::Events::WriteSetReservedV2,
           Coordinator::Write::Events::WriteSetExpandedV2,
           Coordinator::Write::Events::WriteSetRenewedV2,
           Coordinator::Write::Events::WriteSetReleasedV2,
           Coordinator::Read::CandidateSubmissionViewV2,
           Coordinator::Write::Events::AttemptCompletedV1
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
