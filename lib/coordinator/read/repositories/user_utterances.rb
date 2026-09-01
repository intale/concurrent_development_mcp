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

      def store(event:, utterance:)
        Coordinator::Read::UserUtterance.create!(
          message_id: utterance.message_id,
          conversation_id: utterance.conversation_id,
          text: utterance.text,
          source: utterance.source,
          anchors: utterance.anchors.to_h,
          actor_kind: event.metadata.fetch("actor_kind"),
          actor_id: event.metadata.fetch("actor_id"),
          policy_status: "evidence_only",
          event_id: event.id,
          event_type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          recorded_at_domain: utterance.recorded_at
        )
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
