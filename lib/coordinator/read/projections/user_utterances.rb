# frozen_string_literal: true

module Coordinator::Read::Projections
  class UserUtterances
    def initialize(patches:, anchors: {})
      @patches, @anchors = patches, anchors
    end

    def apply(event)
      data = event.data
      identity = { message_id: data.fetch("message_id") }
      case event.type
      when "UserUtteranceRecorded", "UserUtteranceForwardedByAgent"
        @patches.insert(identity.merge(
          Source.reference(event).except(:type),
          conversation_id: data.fetch("conversation_id"), text: data.fetch("text"),
          source: data.fetch("source") == "user" ? "mcp_client" : data.fetch("source"),
          anchors: empty_anchors, actor_kind: event.metadata.fetch("actor_kind"), actor_id: event.metadata.fetch("actor_id"),
          policy_status: "evidence_only", event_type: event.type,
          causation_id: event.causation_id, correlation_id: event.correlation_id, recorded_at_domain: event.created_at,
          created_at: event.created_at, updated_at: event.created_at
        ))
      when "GuidanceMessageAnchored"
        change_anchor(identity, data.fetch("anchor_kind"), data.fetch("anchor_id"))
      end
      @patches.touch(identity, time: event.created_at)
      nil
    end

    private

    def change_anchor(identity, kind, id)
      key = identity.fetch(:message_id)
      anchors = @anchors.fetch(key) { empty_anchors }.dup
      if kind == "repository"
        anchors["repository_ids"] = (anchors.fetch("repository_ids") + [ id ]).uniq
      else
        anchors["#{kind}_id"] = id
      end
      @anchors[key] = anchors
      @patches.assign(identity.merge(anchors:))
      nil
    end

    def empty_anchors
      { "repository_ids" => [], "change_set_id" => nil, "work_item_id" => nil, "attempt_id" => nil }
    end
  end
end
