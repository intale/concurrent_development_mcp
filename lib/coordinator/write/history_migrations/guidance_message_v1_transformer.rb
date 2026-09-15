# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class GuidanceMessageV1Transformer
      include Dry::Monads[:result]

      ANCHOR_TARGETS = {
        "repository" => [ "DevelopmentPlanning", "Repository", "repository" ],
        "change_set" => [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        "work_item" => [ "DevelopmentExecution", "WorkItem", "work-item" ],
        "attempt" => [ "DevelopmentExecution", "Attempt", "attempt" ]
      }.freeze

      def initialize(stream_identity_allocator:, entity_reference_resolver:)
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        conversation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "HumanGuidance",
          target_stream_name: "Conversation",
          identity_role: "conversation"
        )
        return conversation if conversation.failure?

        anchors = transformed_anchors(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return anchors if anchors.failure?

        Success(
          facts(
            source_payload,
            source_event:,
            target_stream: conversation.value!.target_stream,
            anchors: anchors.value!
          )
        )
      end

      private

      def transformed_anchors(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        resolved = []
        source_anchors(source_payload).each do |kind, source_id|
          target = ANCHOR_TARGETS.fetch(kind)
          allocation = @entity_reference_resolver.call(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_stream: StreamReference.new(
              context: target.fetch(0),
              stream_name: target.fetch(1),
              stream_id: source_id
            ),
            target_stream_context: target.fetch(0),
            target_stream_name: target.fetch(1),
            identity_role: target.fetch(2)
          )
          return allocation if allocation.failure?

          resolved << [ kind, allocation.value!.target_stream.stream_id ]
        end
        Success(resolved.freeze)
      end

      def source_anchors(source)
        anchors = source.anchors.repository_ids.map { [ "repository", _1 ] }
        anchors << [ "change_set", source.anchors.change_set_id ] if source.anchors.change_set_id
        anchors << [ "work_item", source.anchors.work_item_id ] if source.anchors.work_item_id
        anchors << [ "attempt", source.anchors.attempt_id ] if source.anchors.attempt_id
        anchors
      end

      def facts(source, source_event:, target_stream:, anchors:)
        conversation_id = target_stream.stream_id
        message_id = source_event.id
        common_markers = [ "conversation:#{conversation_id}", "message:#{message_id}" ]
        utterance = TransformedFactV1.new(
          target_stream:,
          event: utterance_event(source, conversation_id:, message_id:),
          markers: common_markers,
          step_name: utterance_step_name(source)
        )
        anchor_facts = anchors.each_with_index.map do |(kind, anchor_id), index|
          TransformedFactV1.new(
            target_stream:,
            event: Events::GuidanceMessageAnchoredV1.new(
              conversation_id:,
              message_id:,
              anchor_kind: kind,
              anchor_id:
            ),
            markers: common_markers + [ "#{kind.tr('_', '-')}:#{anchor_id}" ],
            step_name: format("anchor-guidance-message-%s-%02d", kind, index + 1)
          )
        end
        [ utterance, *anchor_facts ]
      end

      def utterance_event(source, conversation_id:, message_id:)
        attributes = {
          conversation_id:,
          message_id:,
          source: source.source == "mcp_client" ? "user" : source.source,
          text: source.text
        }
        if source.is_a?(Events::UserUtteranceRecordedV1)
          Events::UserUtteranceRecordedV2.new(attributes)
        else
          Events::UserUtteranceForwardedByAgentV2.new(attributes)
        end
      end

      def utterance_step_name(source)
        return "record-user-utterance" if source.is_a?(Events::UserUtteranceRecordedV1)

        "forward-user-utterance"
      end
    end
  end
end
