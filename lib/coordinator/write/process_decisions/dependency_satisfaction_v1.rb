# frozen_string_literal: true

module Coordinator::Write
  module ProcessDecisions
    class DependencySatisfactionV1 < Value
      attribute :schema, Types::String.enum("process-decision/dependency-satisfaction/v1")
      attribute :process_manager, Types::String.enum("build-progress")
      attribute :policy_version, Types::String.enum("dependency-satisfaction/v1")
      attribute :source_event, EventReference
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :process_step, Types::String.enum("satisfy-work-item-dependency")

      def component_markers
        [
          "process-manager:#{process_manager}",
          "policy-version:#{policy_version}",
          "source-event-id:#{source_event.event_id}",
          "source-stream-context:#{source_event.stream_context}",
          "source-stream-name:#{source_event.stream_name}",
          "source-stream-id:#{source_event.stream_id}",
          "source-stream-revision:#{source_event.stream_revision}",
          "change-set:#{change_set_id}",
          "dependency:#{dependency_id}",
          "process-step:#{process_step}"
        ].freeze
      end
    end
  end
end
