# frozen_string_literal: true

module Coordinator::Write
  class StreamFactory
    def command(command_id)
      StreamReference.new(context: "CoordinatorControl", stream_name: "Command", stream_id: command_id)
    end

    def coordination_task(task_id)
      StreamReference.new(context: "CoordinatorControl", stream_name: "CoordinationTask", stream_id: task_id)
    end

    def change_set(change_set_id)
      StreamReference.new(
        context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        stream_id: change_set_id
      )
    end

    def work_item(work_item_id)
      StreamReference.new(
        context: "DevelopmentExecution",
        stream_name: "WorkItem",
        stream_id: work_item_id
      )
    end

    def attempt(attempt_id)
      StreamReference.new(
        context: "DevelopmentExecution",
        stream_name: "Attempt",
        stream_id: attempt_id
      )
    end

    def resource_lease(resource_key_hash)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "ResourceLease",
        stream_id: resource_key_hash
      )
    end
  end
end
