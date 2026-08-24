# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class MergeSnapshotGet < QueryTool
        tool_name "merge_snapshot_get"
        title "Get an available merge snapshot"
        description "Read the latest available attributed merge-snapshot projection without a freshness gate."
        input_schema Schemas.merge_snapshot_get
        query "queries.merge_snapshot_get"
      end
    end
  end
end
