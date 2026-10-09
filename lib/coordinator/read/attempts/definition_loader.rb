# frozen_string_literal: true

module Coordinator::Read
  module Attempts
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

      def call(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          Coordinator::Write::EventQueries::ATTEMPT_DEFINITION_FOR_PROJECTION
        )
        facts = events.to_h { |event| [ event.type, [ load_event(event), event ] ] }
        authorized, authorized_event = fetch_fact(facts, "AttemptAuthorized")
        started, started_event = fetch_fact(facts, "AttemptStarted")
        membership, = fetch_fact(facts, "AttemptAssignedToWorkItem")
        agent, = fetch_fact(facts, "AttemptAssignedToAgent")
        snapshot, = fetch_fact(facts, "AttemptBaseSnapshotRecorded")
        identities = [ authorized, membership, agent, snapshot, started ].map(&:attempt_id)
        unless identities.all? { _1 == attempt_id }
          raise InvalidProjectionSource, "Attempt definition facts disagree on attempt_id"
        end

        build_view(
          attempt_id:,
          change_set_id: membership.change_set_id,
          work_item_id: membership.work_item_id,
          agent_id: agent.agent_id,
          base_snapshots: [
            Coordinator::Write::RepositorySnapshotV1.new(
              repository_id: snapshot.repository_id,
              object_format: snapshot.object_format,
              commit_oid: snapshot.commit_oid
            )
          ],
          authorization_event: authorized_event,
          authorized_at: timestamp(authorized_event),
          started_at: timestamp(started_event)
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def build_view(**attributes)
        AttemptDefinitionViewV1.new(**attributes)
      end

      def fetch_fact(facts, type)
        facts.fetch(type) { raise InvalidProjectionSource, "Attempt is missing #{type}" }
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
