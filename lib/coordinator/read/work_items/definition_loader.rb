# frozen_string_literal: true

module Coordinator::Read
  module WorkItems
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

      def call(work_item_id)
        events = @event_store.read(
          @stream_factory.work_item(work_item_id),
          Coordinator::Write::EventQueries::WORK_ITEM_DEFINITION_FOR_PROJECTION
        )
        facts = events.to_h { |event| [ event.type, [ load_event(event), event ] ] }
        created, created_event = fetch_fact(facts, "WorkItemCreated")
        if created.is_a?(Coordinator::Write::Events::WorkItemCreatedV1)
          return build_view(
            work_item_id:,
            change_set_id: created.change_set_id,
            repository_id: created.repository_id,
            goal: created.goal,
            acceptance_criteria: created.acceptance_criteria,
            competitive_mode: created.competitive_mode,
            created_at: timestamp(created_event)
          )
        end

        membership, = fetch_fact(facts, "WorkItemAddedToChangeSet")
        repository, = fetch_fact(facts, "WorkItemAssignedToRepository")
        goal, = fetch_fact(facts, "WorkItemGoalDefined")
        criteria, = fetch_fact(facts, "WorkItemAcceptanceCriteriaDefined")
        competitive, = fetch_fact(facts, "WorkItemCompetitiveModeSelected")
        identities = [ created, membership, repository, goal, criteria, competitive ].map(&:work_item_id)
        unless identities.all? { _1 == work_item_id }
          raise InvalidProjectionSource, "WorkItem definition facts disagree on work_item_id"
        end

        build_view(
          work_item_id:,
          change_set_id: membership.change_set_id,
          repository_id: repository.repository_id,
          goal: goal.goal,
          acceptance_criteria: criteria.acceptance_criteria,
          competitive_mode: competitive.competitive_mode,
          created_at: timestamp(created_event)
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def build_view(**attributes)
        WorkItemDefinitionViewV1.new(**attributes)
      end

      def fetch_fact(facts, type)
        facts.fetch(type) { raise InvalidProjectionSource, "WorkItem is missing #{type}" }
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
