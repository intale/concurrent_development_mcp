# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionPartitionBuilder
      def call(definition)
        scope = definition.document.scope
        topic_root = definition.document.topic_root
        anchors = narrowest_anchors(scope)

        anchors.map do |anchor|
          kind = anchor.fetch(:kind)
          id = anchor.fetch(:id)
          DecisionPartitionV1.new(
            partition_id: "#{kind}:#{id}:#{topic_root}",
            topic_root:,
            anchor_kind: kind,
            anchor_id: id
          )
        end.sort_by { _1.partition_id.b }.freeze
      end

      private

      def narrowest_anchors(scope)
        return [ { kind: "candidate", id: scope.candidate_id } ] if scope.candidate_id
        return [ { kind: "attempt", id: scope.attempt_id } ] if scope.attempt_id
        return [ { kind: "workitem", id: scope.work_item_id } ] if scope.work_item_id
        return [ { kind: "changeset", id: scope.change_set_id } ] if scope.change_set_id
        unless scope.repository_ids.empty?
          return scope.repository_ids.uniq.sort_by(&:b).map { { kind: "repo", id: _1 } }
        end
        return [ { kind: "workspace", id: scope.workspace_id } ] if scope.workspace_id

        []
      end
    end
  end
end
