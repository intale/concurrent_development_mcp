# frozen_string_literal: true

module Coordinator::Read::Projections
  class DecisionPartitions
    def call(definition)
      scope, root = definition.fetch(:scope), definition.fetch(:topic).fetch(:topic_id).split(".", 2).first
      anchor = [ [ :candidate_id, "candidate" ], [ :attempt_id, "attempt" ], [ :work_item_id, "workitem" ], [ :change_set_id, "changeset" ] ]
        .find { |key, _| scope[key] }
      anchors = if anchor
                  [ [ anchor.last, scope.fetch(anchor.first) ] ]
      elsif scope.fetch(:repository_ids).any?
                  scope.fetch(:repository_ids).uniq.map { [ "repo", _1 ] }
      elsif scope[:workspace_id]
                  [ [ "workspace", scope.fetch(:workspace_id) ] ]
      else
                  []
      end
      anchors.map { |kind, id| { partition_id: "#{kind}:#{id}:#{root}", topic_root: root, anchor_kind: kind, anchor_id: id } }
        .sort_by { _1.fetch(:partition_id).b }
    end
  end
end
