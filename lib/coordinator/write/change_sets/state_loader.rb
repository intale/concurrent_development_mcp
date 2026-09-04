# frozen_string_literal: true

module Coordinator::Write
  module ChangeSets
    class StateLoader
      OWN_EVENT_TYPES = %w[
        ChangeSetCreated
        ChangeSetGoalDefined
        ChangeSetAcceptanceCriteriaDefined
        WorkItemAddedToChangeSet
        WorkItemDependencyDeclared
        WorkItemDependencySatisfied
        ChangeSetActivated
        ChangeSetReleaseSetLinked
        ChangeSetCompleted
      ].freeze
      MEMBER_EVENT_TYPES = %w[
        WorkItemAddedToChangeSet
        WorkItemDependencyDeclared
        WorkItemDependencySatisfied
      ].freeze
      MAXIMUM_OWN_EVENTS = 1_106
      MAXIMUM_MEMBER_EVENTS = 1_100

      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(change_set_id)
        own = @event_store.read(
          @stream_factory.change_set(change_set_id),
          EventReadCriteria.new(
            event_types: OWN_EVENT_TYPES,
            maximum_count: MAXIMUM_OWN_EVENTS,
            direction: :asc
          )
        )
        members = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentExecution",
            stream_name: "WorkItem",
            event_types: MEMBER_EVENT_TYPES,
            markers: [ "change-set:#{change_set_id}" ],
            maximum_count: MAXIMUM_MEMBER_EVENTS,
            direction: :asc
          )
        )

        events = (own + members).uniq(&:id).sort_by(&:global_position).map { load_event(_1) }
        Domain::ChangeSets::State.reduce(events)
      end

      private

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
