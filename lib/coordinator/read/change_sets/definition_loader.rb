# frozen_string_literal: true

module Coordinator::Read
  module ChangeSets
    class DefinitionLoader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(change_set_id)
        events = @event_store.read(
          @stream_factory.change_set(change_set_id),
          Coordinator::Write::EventQueries::CHANGE_SET_DEFINITION_FOR_PROJECTION
        )
        facts = events.to_h { |event| [ event.type, [ load_event(event), event ] ] }
        created, created_event = fetch_fact(facts, "ChangeSetCreated")

        goal, = fetch_fact(facts, "ChangeSetGoalDefined")
        criteria, = fetch_fact(facts, "ChangeSetAcceptanceCriteriaDefined")
        identities = [ created.change_set_id, goal.change_set_id, criteria.change_set_id ]
        unless identities.all? { _1 == change_set_id }
          raise InvalidProjectionSource, "ChangeSet definition facts disagree on change_set_id"
        end

        build_view(
          change_set_id:,
          goal: goal.goal,
          acceptance_criteria: criteria.acceptance_criteria,
          created_at: timestamp(created_event)
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def build_view(**attributes)
        ChangeSetDefinitionViewV1.new(**attributes)
      end

      def fetch_fact(facts, type)
        facts.fetch(type) { raise InvalidProjectionSource, "ChangeSet is missing #{type}" }
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def timestamp(event)
        event.created_at.utc.iso8601(6)
      end
    end
  end
end
