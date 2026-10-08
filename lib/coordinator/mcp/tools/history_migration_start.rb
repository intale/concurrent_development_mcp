# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class HistoryMigrationStart < MutationTool
        tool_name "history_migration_start"
        title "Start an event history migration"
        description "Freeze a bounded source range and start an asynchronous cross-store migration Saga. Optional lower bound and canonical command selection transfer only a closed new Development Artifact suffix into an accepted target; maintenance and base history are excluded."
        input_schema Schemas.history_migration_start
        operation "operations.submit_start_history_migration_task"
      end
    end
  end
end
