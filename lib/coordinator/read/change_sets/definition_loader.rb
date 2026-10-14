# frozen_string_literal: true

module Coordinator::Read::ChangeSets
  class DefinitionLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(change_set_id)
      facts = @event_store.read(@stream_factory.change_set(change_set_id),
        Coordinator::Write::EventQueries::CHANGE_SET_DEFINITION_FOR_PROJECTION).to_h { [ _1.type, _1 ] }
      { change_set_id:, goal: facts.fetch("ChangeSetGoalDefined").data.fetch("goal"),
        acceptance_criteria: facts.fetch("ChangeSetAcceptanceCriteriaDefined").data.fetch("acceptance_criteria"),
        created_at: facts.fetch("ChangeSetCreated").created_at.utc.iso8601(6) }
    end
  end
end
