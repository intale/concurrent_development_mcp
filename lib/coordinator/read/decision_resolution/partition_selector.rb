# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class PartitionSelector
      TOPIC_ROOT = "testing"

      def call(context)
        anchors = []
        anchors << [ "workspace", context.workspace_id ] if context.workspace_id
        anchors.concat(
          [
            [ "repo", context.repository_id ],
            [ "changeset", context.change_set_id ],
            [ "workitem", context.work_item_id ],
            [ "attempt", context.attempt_id ]
          ]
        )

        anchors.map do |kind, id|
          Coordinator::Write::Decisions::DecisionPartitionV1.new(
            partition_id: "#{kind}:#{id}:#{TOPIC_ROOT}",
            topic_root: TOPIC_ROOT,
            anchor_kind: kind,
            anchor_id: id
          )
        end.freeze
      end
    end
  end
end
