# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class UserUtterances
      def fetch(message_id)
        record = Coordinator::Read::UserUtterance.find_by(message_id:)
        build(record)
      end

      def fetch_many(message_ids)
        records = Coordinator::Read::UserUtterance.where(message_id: message_ids).index_by(&:message_id)
        message_ids.filter_map { build(records[_1]) }
      end

      private

      def build(record)
        return unless record

        GuidanceUtteranceV1.new(
          message_id: record.message_id,
          conversation_id: record.conversation_id,
          text: record.text,
          source: record.source,
          anchors: Coordinator::Write::GuidanceAnchorsV1.new(deep_symbolize(record.anchors)),
          actor: AttributedActorV1.new(
            kind: record.actor_kind,
            id: record.actor_id,
            authenticated: false
          ),
          policy_status: record.policy_status,
          recorded_at: record.recorded_at_domain.utc.iso8601(6),
          event: Coordinator::Write::EventReference.new(
            event_id: record.event_id,
            type: record.event_type,
            stream_context: record.stream_context,
            stream_name: record.stream_name,
            stream_id: record.stream_id,
            stream_revision: record.stream_revision
          ),
          causation_id: record.causation_id,
          correlation_id: record.correlation_id
        )
      end

      def deep_symbolize(value)
        value.to_h { |key, nested| [ key.to_sym, nested ] }
      end
    end
  end
end
