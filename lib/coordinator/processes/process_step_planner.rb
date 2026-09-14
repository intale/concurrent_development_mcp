# frozen_string_literal: true

module Coordinator::Processes
  class ProcessStepPlanner
    SYSTEM_ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "process-step-dispatch")

    def initialize(
      event_store:,
      planner: Coordinator::Write::ProcessSteps::Planner.new(event_store:),
      failure_operation:
        Coordinator::Write::Operations::ExecuteRecordProcessStepDispatchFailure.new(event_store:),
      id_generator: Coordinator::Shared::IdGenerator.new,
      retryability: Coordinator::Write::Tasks::CommandRejectionRetryability.new
    )
      @planner = planner
      @failure_operation = failure_operation
      @id_generator = id_generator
      @retryability = retryability
    end

    def call(source_event:, process_name:, step_name:, subject_kind:, subject_id:, rule_version:, allocate_target_entity:)
      result = @planner.call(
        source_event:,
        process_name:,
        step_name:,
        subject_kind:,
        subject_id:,
        rule_version:,
        allocate_target_entity:
      )
      return result.value! if result.success?

      failure = result.failure
      raise ProcessStepPlanningRejected,
            "#{process_name}/#{step_name} could not be planned: #{failure.code} - #{failure.message}"
    end

    def record_dispatch_failure(process_step:, failure:)
      result = @failure_operation.call_command(
        Coordinator::Write::Commands::RecordProcessStepDispatchFailure.new(
          command_id: @id_generator.uuid_v7,
          actor: SYSTEM_ACTOR,
          process_step_id: process_step.process_step_id,
          target_command_id: process_step.target_command_id,
          code: failure.code.to_s,
          reason: failure.message,
          retryable: @retryability.call(failure)
        ),
        caused_by: process_step.event
      )
      return result.value! if result.success?

      rejected = result.failure
      raise ProcessStepPlanningRejected,
            "dispatch failure could not be recorded: #{rejected.code} - #{rejected.message}"
    end
  end
end
