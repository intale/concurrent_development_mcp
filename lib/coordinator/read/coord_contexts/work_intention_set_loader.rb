# frozen_string_literal: true

module Coordinator::Read::CoordContexts
  # Only immutable parent/Resource facts and the trigger's exact preceding deadline.
  # Mutable set/member state is folded from delivery, never fetched from the future.
  class WorkIntentionSetLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(event)
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      stream = @stream_factory.resource_work_intention(data.fetch(:intention_id))
      declaration = @event_store.read(stream, Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceWorkIntentionDeclared" ], maximum_count: 1, direction: :asc)).first
      declared = Coordinator::Read::CommandResults::Source.document(declaration.data)
      created = @event_store.read(@stream_factory.work_intention_set(declared.fetch(:set_id)), Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WorkIntentionSetCreated" ], maximum_count: 1, direction: :asc)).first
      resource = @event_store.read(@stream_factory.resource(declared.fetch(:resource_id)), Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceRegistered" ], maximum_count: 1, direction: :asc)).first
      prior = if event.type == "ResourceWorkIntentionRenewed"
        @event_store.read_latest(stream, Coordinator::Write::LatestEventReadCriteria.new(
          event_types: [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionRenewed" ], from_revision: event.stream_revision - 1))
      end
      declared.slice(:set_id, :change_set_id, :work_item_id, :attempt_id, :repository_id, :agent_id).merge(
        policy_version: "coordinator-work-intention/v1",
        member: declared.slice(:intention_id, :resource_id, :base_blob_oid, :mode, :purpose, :context, :fencing_token).merge(
          resource_kind: resource.data.fetch("kind"), resource_path: resource.data.fetch("normalized_path")),
        declared_expires_at: declared.fetch(:expires_at), expires_at: data[:expires_at],
        created_event: Coordinator::Read::Projections::Source.reference(created), declared_at: created.created_at.utc.iso8601(6),
        expanded: declaration.metadata.fetch("command_id") != created.metadata.fetch("command_id"),
        previous_expires_at: prior&.data&.fetch("expires_at"))
    end
  end
end
