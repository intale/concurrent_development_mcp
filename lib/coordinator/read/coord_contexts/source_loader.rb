# frozen_string_literal: true

module Coordinator::Read::CoordContexts
  class SourceLoader
    COMPONENT_TYPES = %w[ChangeSetCreated ChangeSetGoalDefined WorkItemCreated WorkItemAddedToChangeSet
      WorkItemAssignedToRepository WorkItemGoalDefined WorkItemAcceptanceCriteriaDefined AttemptAuthorized
      AttemptAssignedToWorkItem AttemptAssignedToAgent AttemptBaseSnapshotRecorded WorkItemOutputRecorded
      ResourceRegistered WorkIntentionSetCreated WorkIntentionAddedToSet].freeze

    def initialize(event_store:, submission_loader:,
      change_set_definition_loader: Coordinator::Read::ChangeSets::DefinitionLoader.new(event_store:),
      work_item_definition_loader: Coordinator::Read::WorkItems::DefinitionLoader.new(event_store:),
      work_item_completion_loader: Coordinator::Read::WorkItems::CompletionLoader.new(event_store:),
      attempt_definition_loader: Coordinator::Read::Attempts::DefinitionLoader.new(event_store:),
      work_intention_set_loader: WorkIntentionSetLoader.new(event_store:))
      @submission_loader, @change_sets, @work_items = submission_loader, change_set_definition_loader, work_item_definition_loader
      @completions, @attempts, @intention_sets = work_item_completion_loader, attempt_definition_loader, work_intention_set_loader
    end

    def call(event)
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      return if COMPONENT_TYPES.include?(event.type)

      case event.type
      when "ChangeSetAcceptanceCriteriaDefined" then @change_sets.call(data.fetch(:change_set_id))
      when "WorkItemCompetitiveModeSelected" then @work_items.call(data.fetch(:work_item_id))
      when "AttemptStarted" then @attempts.call(data.fetch(:attempt_id))
      when "WorkItemCompleted" then @completions.call(data.fetch(:work_item_id), terminal_event_id: event.id)
      when "AttemptAbandoned"
        @attempts.call(data.fetch(:attempt_id)).slice(:attempt_id, :change_set_id, :work_item_id, :agent_id).merge(reason: data.fetch(:reason))
      when "AttemptCompleted"
        definition = @attempts.call(data.fetch(:attempt_id))
        definition.slice(:attempt_id, :change_set_id, :work_item_id).merge(
          @completions.call(definition.fetch(:work_item_id)).slice(:candidate_id, :candidate_event))
      when "CandidateSubmitted" then candidate(data.fetch(:candidate_id))
      when "ResourceWorkIntentionDeclared", "ResourceWorkIntentionRenewed", "ResourceWorkIntentionWithdrawn", "ResourceWorkIntentionExpired"
        @intention_sets.call(event)
      else data
      end
    end

    private

    def candidate(id)
      source = @submission_loader.call(id)
      { candidate_id: id, candidate_event: Coordinator::Read::Projections::Source.reference(source.submitted_event),
        change_set_id: source.change_set_id, work_item_id: source.work_item_id, attempt_id: source.attempt_id,
        repository_id: source.repository_id, target_branch: source.target_branch, object_format: source.object_format,
        base_commit_oid: source.base_commit_oid, head_commit_oid: source.head_commit_oid, checkpoint_kind: source.checkpoint_kind,
        manifest_digest: source.manifest_digest, build_context_digest: source.build_context_digest,
        attached_at: source.submitted_event.created_at.utc.iso8601(6) }
    end
  end
end
