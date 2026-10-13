# frozen_string_literal: true

module Coordinator::Write
  module CommandResults
    class ReleaseSetPreparationLoader
      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store, @stream_factory, @schema_registry = event_store, stream_factory, schema_registry
      end

      def call(release_set_id)
        created = nil
        members = []
        prepared_event = nil
        @event_store.read(@stream_factory.release_set(release_set_id), EventQueries::RELEASE_SET_PREPARATION).each do |event|
          payload = @schema_registry.load(type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data)
          case payload
          when Events::ReleaseSetCreatedV1 then created = payload
          when Events::ReleaseSetMemberAddedV1
            members << ReleaseSets::MemberSummaryV2.new(position: payload.member_position,
              repository_id: payload.repository_id, merge_snapshot_id: payload.merge_snapshot_id,
              ordered_candidate_ids: payload.ordered_candidate_ids, authorization_event: payload.authorization_event)
          when Events::ReleaseSetPreparedV2 then prepared_event = event
          end
        end
        unless created && prepared_event && created.release_set_id == release_set_id &&
               members.map(&:position) == (1..members.length).to_a
          raise InvalidCommandHistory, "ReleaseSet preparation facts are incomplete"
        end
        ReleaseSetPreparationV1.new(release_set_id:, change_set_id: created.change_set_id, ordered_members: members,
          release_digest: prepared_event.metadata.fetch("release_digest"), policy_version: prepared_event.metadata.fetch("policy_version"))
      end
    end
  end
end
