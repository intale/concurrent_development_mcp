# frozen_string_literal: true

module Coordinator::Read::WorkItems
  class DefinitionLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(work_item_id)
      facts = @event_store.read(@stream_factory.work_item(work_item_id),
        Coordinator::Write::EventQueries::WORK_ITEM_DEFINITION_FOR_PROJECTION).to_h { [ _1.type, _1 ] }
      { work_item_id:, change_set_id: facts.fetch("WorkItemAddedToChangeSet").data.fetch("change_set_id"),
        repository_id: facts.fetch("WorkItemAssignedToRepository").data.fetch("repository_id"),
        goal: facts.fetch("WorkItemGoalDefined").data.fetch("goal"),
        acceptance_criteria: facts.fetch("WorkItemAcceptanceCriteriaDefined").data.fetch("acceptance_criteria"),
        competitive_mode: facts.fetch("WorkItemCompetitiveModeSelected").data.fetch("competitive_mode"),
        created_at: facts.fetch("WorkItemCreated").created_at.utc.iso8601(6) }
    end
  end
end
