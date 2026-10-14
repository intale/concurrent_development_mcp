# frozen_string_literal: true

module Coordinator::Read::Attempts
  class DefinitionLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(attempt_id)
      facts = @event_store.read(@stream_factory.attempt(attempt_id),
        Coordinator::Write::EventQueries::ATTEMPT_DEFINITION_FOR_PROJECTION).to_h { [ _1.type, _1 ] }
      authorization, started = facts.values_at("AttemptAuthorized", "AttemptStarted")
      { attempt_id:, **Coordinator::Read::CommandResults::Source.document(facts.fetch("AttemptAssignedToWorkItem").data).slice(:change_set_id, :work_item_id),
        agent_id: facts.fetch("AttemptAssignedToAgent").data.fetch("agent_id"),
        base_snapshots: [ Coordinator::Read::CommandResults::Source.document(facts.fetch("AttemptBaseSnapshotRecorded").data).slice(:repository_id, :object_format, :commit_oid) ],
        authorization_event: Coordinator::Read::Projections::Source.reference(authorization), authorized_global_position: authorization.global_position,
        authorized_at: authorization.created_at.utc.iso8601(6), started_at: started.created_at.utc.iso8601(6) }
    end
  end
end
