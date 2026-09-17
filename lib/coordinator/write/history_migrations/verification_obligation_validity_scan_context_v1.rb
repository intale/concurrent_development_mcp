# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class VerificationObligationValidityScanContextV1 < Value
      attribute :source_started, Events::VerificationObligationValidityScanStartedV1
      attribute :source_started_event, Types.Instance(PgEventstore::Event)
      attribute? :target_started_event, EventReference.optional.default(nil)
      attribute :target_stream, StreamReference
      attribute :scan_id, Types::UuidV7
      attribute :change_set_id, Types::UuidV7
      attribute :superseding_partition_event, EventReference

      def source_started_reference
        EventReference.new(
          event_id: source_started_event.id,
          type: source_started_event.type,
          stream_context: source_started_event.stream.context,
          stream_name: source_started_event.stream.stream_name,
          stream_id: source_started_event.stream.stream_id,
          stream_revision: source_started_event.stream_revision
        )
      end

      def markers
        [
          "verification-obligation-validity-scan:#{scan_id}",
          "change-set:#{change_set_id}"
        ].freeze
      end

      def start_markers
        (markers + [
          "superseding-partition-event:#{superseding_partition_event.event_id}"
        ]).freeze
      end
    end
  end
end
