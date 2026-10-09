# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class UserUtterances
      include EventTimestamped

      def fetch(message_id)
        record = Coordinator::Read::UserUtterance.find_by(message_id:)
        build(record)
      end

      def fetch_many(message_ids)
        records = Coordinator::Read::UserUtterance.where(message_id: message_ids).index_by(&:message_id)
        message_ids.filter_map { build(records[_1]) }
      end

      def store(event:, utterance:)
        create_from_event(Coordinator::Read::UserUtterance, event:, attributes: {
          message_id: utterance.message_id,
          conversation_id: utterance.conversation_id,
          text: utterance.text,
          source: utterance.source == "user" ? "mcp_client" : utterance.source,
          anchors: empty_anchors,
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
          recorded_at_domain: event.created_at
        })
      end

      def add_anchor(event:, anchor:)
        record = Coordinator::Read::UserUtterance.find(anchor.message_id)
        anchors = deep_symbolize(record.anchors)
        case anchor.anchor_kind
        when "repository"
          anchors[:repository_ids] = (anchors.fetch(:repository_ids) + [ anchor.anchor_id ]).uniq
        when "change_set", "work_item", "attempt"
          anchors[:"#{anchor.anchor_kind}_id"] = anchor.anchor_id
        end
        save_from_event(record, event:, attributes: { anchors: })
      end

      private

      def empty_anchors
        {
          repository_ids: [],
          change_set_id: nil,
          work_item_id: nil,
          attempt_id: nil
        }
      end

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
