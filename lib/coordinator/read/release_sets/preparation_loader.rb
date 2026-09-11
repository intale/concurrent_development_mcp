# frozen_string_literal: true

module Coordinator::Read
  module ReleaseSets
    class PreparationLoader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(release_set_id)
        created = nil
        members = []
        prepared = nil
        @event_store.read(
          @stream_factory.release_set(release_set_id),
          Coordinator::Write::EventQueries::RELEASE_SET_PREPARATION
        ).each do |event|
          payload = load_event(event)
          case payload
          when Coordinator::Write::Events::ReleaseSetCreatedV1
            created = payload
          when Coordinator::Write::Events::ReleaseSetMemberAddedV1
            members << ReleaseSetMemberViewV1.new(
              position: payload.member_position,
              repository_id: payload.repository_id,
              merge_snapshot_id: payload.merge_snapshot_id,
              ordered_candidate_ids: payload.ordered_candidate_ids,
              authorization_event: payload.authorization_event
            )
          when Coordinator::Write::Events::ReleaseSetPreparedV2
            prepared = [ payload, event ]
          end
        end
        payload, event = prepared
        unless created && payload && created.release_set_id == release_set_id &&
               members.map(&:position) == (1..members.length).to_a
          raise InvalidProjectionSource, "ReleaseSet preparation facts are incomplete"
        end

        ReleaseSetPreparationViewV2.new(
          release_set_id:,
          change_set_id: created.change_set_id,
          ordered_members: members.freeze,
          release_digest: event.metadata.fetch("release_digest"),
          policy_version: event.metadata.fetch("policy_version")
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
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
