# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class ReleaseSetMigrationContextV1 < Value
      Member = Types.Instance(ReleaseSetMemberMigrationV1)

      attribute :source_preparation, Events::ReleaseSetPreparedV1
      attribute :source_preparation_event, Types.Instance(PgEventstore::Event)
      attribute :target_stream, StreamReference
      attribute :release_set_id, Types::UuidV7
      attribute :change_set_id, Types::UuidV7
      attribute :members,
                Types::Array.of(Member)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )

      def source_preparation_reference
        EventReference.new(
          event_id: source_preparation_event.id,
          type: source_preparation_event.type,
          stream_context: source_preparation_event.stream.context,
          stream_name: source_preparation_event.stream.stream_name,
          stream_id: source_preparation_event.stream.stream_id,
          stream_revision: source_preparation_event.stream_revision
        )
      end

      def member(source_repository_id)
        members.find { _1.source_repository_id == source_repository_id }
      end

      def markers
        [
          "release-set:#{release_set_id}",
          "change-set:#{change_set_id}",
          *members.flat_map do |member|
            target = member.target_member
            [
              "repository:#{target.repository_id}",
              "merge-snapshot:#{target.merge_snapshot_id}",
              "merge-authorization:#{target.authorization_event.stream_id}"
            ]
          end
        ].freeze
      end
    end
  end
end
