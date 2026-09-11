# frozen_string_literal: true

module Coordinator::Read
  module CoordContexts
    class SourceLoader
      def initialize(
        event_store:,
        submission_loader:,
        change_set_definition_loader: ChangeSets::DefinitionLoader.new(event_store:),
        work_item_definition_loader: WorkItems::DefinitionLoader.new(event_store:),
        work_item_completion_loader: WorkItems::CompletionLoader.new(event_store:),
        attempt_definition_loader: Attempts::DefinitionLoader.new(event_store:),
        work_intention_set_loader: WorkIntentionSetLoader.new(event_store:)
      )
        @submission_loader = submission_loader
        @change_set_definition_loader = change_set_definition_loader
        @work_item_definition_loader = work_item_definition_loader
        @work_item_completion_loader = work_item_completion_loader
        @attempt_definition_loader = attempt_definition_loader
        @work_intention_set_loader = work_intention_set_loader
      end

      def call(event, payload)
        case payload
        when Coordinator::Write::Events::CandidateSubmittedV3
          candidate_submission(event, payload)
        when Coordinator::Write::Events::ChangeSetCreatedV2,
             Coordinator::Write::Events::ChangeSetGoalDefinedV1,
             Coordinator::Write::Events::WorkItemCreatedV2,
             Coordinator::Write::Events::WorkItemAddedToChangeSetV2,
             Coordinator::Write::Events::WorkItemAssignedToRepositoryV1,
             Coordinator::Write::Events::WorkItemGoalDefinedV1,
             Coordinator::Write::Events::WorkItemAcceptanceCriteriaDefinedV1,
             Coordinator::Write::Events::AttemptAuthorizedV2,
             Coordinator::Write::Events::AttemptAssignedToWorkItemV1,
             Coordinator::Write::Events::AttemptAssignedToAgentV1,
             Coordinator::Write::Events::AttemptBaseSnapshotRecordedV1,
             Coordinator::Write::Events::WorkItemOutputRecordedV1
          nil
        when Coordinator::Write::Events::ChangeSetAcceptanceCriteriaDefinedV2
          @change_set_definition_loader.call(payload.change_set_id)
        when Coordinator::Write::Events::WorkItemCompetitiveModeSelectedV1
          @work_item_definition_loader.call(payload.work_item_id)
        when Coordinator::Write::Events::AttemptStartedV2
          @attempt_definition_loader.call(payload.attempt_id)
        when Coordinator::Write::Events::WorkItemCompletedV2
          @work_item_completion_loader.call(payload.work_item_id, terminal_event_id: event.id)
        when Coordinator::Write::Events::AttemptAbandonedV3
          abandonment(payload, event)
        when Coordinator::Write::Events::AttemptCompletedV2
          completion(payload, event)
        when Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1,
             Coordinator::Write::Events::ResourceWorkIntentionRenewedV1,
             Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1,
             Coordinator::Write::Events::ResourceWorkIntentionExpiredV1
          @work_intention_set_loader.call(event, payload)
        else
          payload
        end
      end

      private

      def candidate_submission(event, payload)
        source = @submission_loader.call(payload.candidate_id)
        unless source.candidate_id == payload.candidate_id && source.submitted_event.id == event.id
          raise InvalidProjectionSource, "Candidate submission evidence does not match its terminal fact"
        end

        source
      end

      def abandonment(payload, event)
        definition = @attempt_definition_loader.call(payload.attempt_id)
        AttemptAbandonmentViewV1.new(
          attempt_id: definition.attempt_id,
          change_set_id: definition.change_set_id,
          work_item_id: definition.work_item_id,
          agent_id: definition.agent_id,
          reason: payload.reason,
          abandoned_at: timestamp(event)
        )
      end

      def completion(payload, event)
        definition = @attempt_definition_loader.call(payload.attempt_id)
        work_item = @work_item_completion_loader.call(definition.work_item_id)
        unless work_item.attempt_id == definition.attempt_id
          raise InvalidProjectionSource, "Attempt completion disagrees with WorkItem selection"
        end

        AttemptCompletionViewV1.new(
          attempt_id: definition.attempt_id,
          change_set_id: definition.change_set_id,
          work_item_id: definition.work_item_id,
          candidate_id: work_item.candidate_id,
          candidate_event: work_item.candidate_event,
          completed_at: timestamp(event)
        )
      end

      def timestamp(event)
        event.created_at.utc.iso8601(6)
      end
    end
  end
end
