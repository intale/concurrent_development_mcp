# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class PartitionSelector
      def call(context, topic_id:)
        topic_root = topic_id.split(".", 2).first
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
            partition_id: "#{kind}:#{id}:#{topic_root}",
            topic_root:,
            anchor_kind: kind,
            anchor_id: id
          )
        end.freeze
      end
    end
  end
end
