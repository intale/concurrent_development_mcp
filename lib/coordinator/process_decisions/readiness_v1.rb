# frozen_string_literal: true

module Coordinator
  module ProcessDecisions
    class ReadinessV1 < Value
      attribute :schema, Types::String.enum("process-decision/readiness/v1")
      attribute :process_manager, Types::String.enum("change-set-readiness")
      attribute :policy_version, Types::String.enum("change-set-readiness/v1")
      attribute :source_event, Types.Instance(EventReference)
      attribute :target_work_item_id, Types::Identifier
      attribute :process_step, Types::String.enum("evaluate-work-item-readiness")

      def component_markers
        [
          "process-manager:#{process_manager}",
          "policy-version:#{policy_version}",
          "source-event-id:#{source_event.event_id}",
          "source-stream-context:#{source_event.stream_context}",
          "source-stream-name:#{source_event.stream_name}",
          "source-stream-id:#{source_event.stream_id}",
          "source-stream-revision:#{source_event.stream_revision}",
          "target-work-item:#{target_work_item_id}",
          "process-step:#{process_step}"
        ].freeze
      end
    end
  end
end
